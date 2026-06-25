import type { NextFunction, Request, Response } from "express";
import { v5 as uuidv5 } from "uuid";
import { query, withTransaction } from "../db/pool.js";
import { HttpError } from "../lib/http-error.js";

/** Must match `supabase/scripts/generate_seed.py` (legacy path) and iOS `ExerciseNameNormalizer`. */
const UUID_NS = "6f2f1e3a-8c4d-5b6e-9f0a-1b2c3d4e5f60";

function normNameKey(name: string): string {
  return name.trim().toLowerCase();
}

function exerciseIdFromKey(nameKey: string): string {
  return uuidv5(`exercise:${nameKey}`, UUID_NS);
}

function programDayId(programId: string, dayIndex: number): string {
  return uuidv5(`day:${programId}:${dayIndex}`, UUID_NS);
}

type InEx = {
  name?: unknown;
  maxWeight?: unknown;
  targetSets?: unknown;
  supersetGroup?: unknown;
  isAmrap?: unknown;
  isWarmup?: unknown;
  notes?: unknown;
};

type InDay = { label?: unknown; exercises?: unknown };

type InProgram = {
  id?: unknown;
  name?: unknown;
  subtitle?: unknown;
  period?: unknown;
  dateRange?: unknown;
  days?: unknown;
  color?: unknown;
  isUserCreated?: unknown;
};

type ParsedEx = {
  name: string;
  maxWeight: string;
  targetSets: number | null;
  supersetGroup: number | null;
  isAmrap: boolean | null;
  isWarmup: boolean | null;
  notes: string | null;
};

type ParsedDay = { label: string; exercises: ParsedEx[] };

function parseProgram(body: unknown): {
  id: string;
  name: string;
  subtitle: string;
  period: string;
  dateRange: string;
  color: string;
  isUserCreated: boolean;
  days: ParsedDay[];
} {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new HttpError(400, "Expected JSON object body");
  }
  const b = body as InProgram;
  const id = typeof b.id === "string" ? b.id.trim() : "";
  if (!id) throw new HttpError(400, "program id required");

  const name = typeof b.name === "string" ? b.name.trim() : "";
  if (!name) throw new HttpError(400, "program name required");

  const subtitle = typeof b.subtitle === "string" ? b.subtitle.trim() : "";
  const period = typeof b.period === "string" ? b.period.trim() : "";
  const dateRange = typeof b.dateRange === "string" ? b.dateRange.trim() : "";
  const color =
    typeof b.color === "string" && b.color.trim().length > 0 ? b.color.trim() : "#66bfcc";

  const isUserCreated = b.isUserCreated === true;

  if (!Array.isArray(b.days) || b.days.length === 0) {
    throw new HttpError(400, "program days must be a non-empty array");
  }

  const days: ParsedDay[] = [];
  for (const rawDay of b.days as InDay[]) {
    if (!rawDay || typeof rawDay !== "object" || Array.isArray(rawDay)) {
      throw new HttpError(400, "Invalid day entry");
    }
    const label = typeof rawDay.label === "string" ? rawDay.label.trim() : "";
    if (!label) throw new HttpError(400, "Each day needs a non-empty label");

    if (!Array.isArray(rawDay.exercises) || rawDay.exercises.length === 0) {
      throw new HttpError(400, `Day "${label}" needs at least one exercise`);
    }

    const exercises: ParsedEx[] = [];
    for (const rawEx of rawDay.exercises as InEx[]) {
      if (!rawEx || typeof rawEx !== "object" || Array.isArray(rawEx)) {
        throw new HttpError(400, "Invalid exercise entry");
      }
      const exName = typeof rawEx.name === "string" ? rawEx.name.trim() : "";
      if (!exName) throw new HttpError(400, "Each exercise needs a non-empty name");

      const maxWeight = typeof rawEx.maxWeight === "string" ? rawEx.maxWeight.trim() : "";

      let targetSets: number | null = null;
      if (rawEx.targetSets !== undefined && rawEx.targetSets !== null) {
        if (typeof rawEx.targetSets !== "number" || !Number.isFinite(rawEx.targetSets)) {
          throw new HttpError(400, "targetSets must be a number when set");
        }
        const ts = Math.round(rawEx.targetSets);
        targetSets = Math.min(20, Math.max(1, ts));
      }

      let supersetGroup: number | null = null;
      if (rawEx.supersetGroup !== undefined && rawEx.supersetGroup !== null) {
        if (typeof rawEx.supersetGroup !== "number" || !Number.isFinite(rawEx.supersetGroup)) {
          throw new HttpError(400, "supersetGroup must be a number when set");
        }
        const g = Math.round(rawEx.supersetGroup);
        if (g >= 1 && g <= 6) supersetGroup = g;
      }

      let isAmrap: boolean | null = null;
      if (rawEx.isAmrap === true) isAmrap = true;
      else if (rawEx.isAmrap === false) isAmrap = false;

      let isWarmup: boolean | null = null;
      if (rawEx.isWarmup === true) isWarmup = true;
      else if (rawEx.isWarmup === false) isWarmup = false;

      let notes: string | null = null;
      if (typeof rawEx.notes === "string") {
        const t = rawEx.notes.trim();
        notes = t.length > 0 ? t : null;
      }

      exercises.push({
        name: exName,
        maxWeight,
        targetSets,
        supersetGroup,
        isAmrap,
        isWarmup,
        notes,
      });
    }
    days.push({ label, exercises });
  }

  return { id, name, subtitle, period, dateRange, color, isUserCreated, days };
}

export async function postPublishCatalogProgram(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const program = parseProgram(req.body);

    const existing = await query<{ id: string }>(
      `SELECT id FROM catalog_programs WHERE id = $1`,
      [program.id]
    );
    if (existing.rows.length === 0) {
      throw new HttpError(
        400,
        "Unknown catalog program id (only existing catalog programs can be published)"
      );
    }

    const nameKeyToDisplay = new Map<string, string>();
    for (const d of program.days) {
      for (const ex of d.exercises) {
        const nk = normNameKey(ex.name);
        if (!nameKeyToDisplay.has(nk)) nameKeyToDisplay.set(nk, ex.name.trim());
      }
    }

    await withTransaction(async (client) => {
      for (const [nk, display] of nameKeyToDisplay) {
        await client.query(
          `INSERT INTO exercises (id, name, name_key) VALUES ($1, $2, $3)
           ON CONFLICT (name_key) DO UPDATE SET name = EXCLUDED.name`,
          [exerciseIdFromKey(nk), display, nk]
        );
      }

      await client.query(
        `UPDATE catalog_programs SET
           name = $2, subtitle = $3, period = $4, date_range = $5, color = $6, is_user_created = $7
         WHERE id = $1`,
        [
          program.id,
          program.name,
          program.subtitle,
          program.period,
          program.dateRange,
          program.color,
          program.isUserCreated,
        ]
      );

      await client.query(`DELETE FROM catalog_program_days WHERE program_id = $1`, [program.id]);

      for (let i = 0; i < program.days.length; i++) {
        const d = program.days[i]!;
        const dayId = programDayId(program.id, i);
        await client.query(
          `INSERT INTO catalog_program_days (id, program_id, day_index, label) VALUES ($1, $2, $3, $4)`,
          [dayId, program.id, i, d.label]
        );
        for (let ei = 0; ei < d.exercises.length; ei++) {
          const ex = d.exercises[ei]!;
          const nk = normNameKey(ex.name);
          await client.query(
            `INSERT INTO catalog_day_exercises
               (program_day_id, exercise_id, sort_order, max_weight, target_sets, superset_group, is_amrap, is_warmup, notes)
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
            [
              dayId,
              exerciseIdFromKey(nk),
              ei,
              ex.maxWeight,
              ex.targetSets,
              ex.supersetGroup,
              ex.isAmrap,
              ex.isWarmup,
              ex.notes,
            ]
          );
        }
      }

      const rel = await client.query<{ version: number }>(
        `SELECT version FROM catalog_release WHERE id = 1 FOR UPDATE`
      );
      const prev = rel.rows[0]?.version;
      const nextVersion = typeof prev === "number" && Number.isFinite(prev) ? prev + 1 : 1;
      await client.query(
        `UPDATE catalog_release SET version = $1, notes = $2, published_at = now() WHERE id = 1`,
        [nextVersion, `publish:${program.id}`]
      );

      return nextVersion;
    }).then((nextVersion) => {
      res.json({ ok: true, programId: program.id, catalogVersion: nextVersion });
    });
  } catch (e) {
    next(e);
  }
}
