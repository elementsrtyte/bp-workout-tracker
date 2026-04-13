import type { NextFunction, Request, Response } from "express";
import { v5 as uuidv5 } from "uuid";
import { HttpError } from "./httpError.js";
import {
  fetchSupabaseAuthUser,
  restFetchServiceRole,
  restJsonServiceRole,
} from "./supabaseData.js";

/** Must match `supabase/scripts/generate_seed.py` and iOS `ExerciseNameNormalizer`. */
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

function catalogAdminAllowlist(): string[] {
  const fromList =
    process.env.CATALOG_ADMIN_EMAILS?.split(",").map((s) => s.trim().toLowerCase()).filter(Boolean) ??
    [];
  const one = process.env.CATALOG_ADMIN_EMAIL?.trim().toLowerCase();
  const set = new Set(fromList);
  if (one) set.add(one);
  return [...set];
}

function assertCatalogAdmin(email: string | null): void {
  const allow = catalogAdminAllowlist();
  if (allow.length === 0) {
    throw new HttpError(503, "Catalog admin is not configured (set CATALOG_ADMIN_EMAILS)");
  }
  if (!email || !allow.includes(email)) {
    throw new HttpError(403, "Not authorized to publish catalog programs");
  }
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

type InDay = {
  label?: unknown;
  exercises?: unknown;
};

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

      const maxWeight =
        typeof rawEx.maxWeight === "string" ? rawEx.maxWeight.trim() : "";

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

/**
 * Dev-only: replace one catalog program graph in Supabase and bump `catalog_release.version`.
 * Caller must pass a valid Supabase user JWT; email must be in CATALOG_ADMIN_EMAILS.
 */
export async function postPublishCatalogProgram(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const auth = req.header("authorization") ?? req.header("Authorization");
    const user = await fetchSupabaseAuthUser(auth);
    assertCatalogAdmin(user.email);

    const program = parseProgram(req.body);

    const existing = await restJsonServiceRole<{ id: string }[]>(
      "catalog_programs",
      "GET",
      undefined,
      `select=id&id=eq.${encodeURIComponent(program.id)}`
    );
    if (!existing?.length) {
      throw new HttpError(
        400,
        "Unknown catalog program id (only existing catalog programs can be published)"
      );
    }

    const nameKeyToDisplay = new Map<string, string>();
    for (const d of program.days) {
      for (const ex of d.exercises) {
        const nk = normNameKey(ex.name);
        if (!nameKeyToDisplay.has(nk)) {
          nameKeyToDisplay.set(nk, ex.name.trim());
        }
      }
    }

    const exerciseRows = [...nameKeyToDisplay.entries()].map(([nk, display]) => ({
      id: exerciseIdFromKey(nk),
      name: display,
      name_key: nk,
    }));

    const upsertEx = await restFetchServiceRole("exercises", {
      method: "POST",
      search: "on_conflict=name_key",
      headers: {
        Prefer: "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(exerciseRows),
    });
    if (!upsertEx.ok) {
      const text = await upsertEx.text();
      throw new HttpError(502, `exercises upsert failed: ${upsertEx.status} ${text.slice(0, 200)}`);
    }

    await restJsonServiceRole(
      "catalog_programs",
      "PATCH",
      {
        name: program.name,
        subtitle: program.subtitle,
        period: program.period,
        date_range: program.dateRange,
        color: program.color,
        is_user_created: program.isUserCreated,
      },
      `id=eq.${encodeURIComponent(program.id)}`
    );

    const del = await restFetchServiceRole("catalog_program_days", {
      method: "DELETE",
      search: `program_id=eq.${encodeURIComponent(program.id)}`,
    });
    if (!del.ok) {
      const text = await del.text();
      throw new HttpError(502, `catalog_program_days delete failed: ${del.status} ${text.slice(0, 200)}`);
    }

    const dayRows = program.days.map((d, i) => ({
      id: programDayId(program.id, i),
      program_id: program.id,
      day_index: i,
      label: d.label,
    }));

    const insDays = await restFetchServiceRole("catalog_program_days", {
      method: "POST",
      headers: { Prefer: "return=minimal" },
      body: JSON.stringify(dayRows),
    });
    if (!insDays.ok) {
      const text = await insDays.text();
      throw new HttpError(502, `catalog_program_days insert failed: ${insDays.status} ${text.slice(0, 200)}`);
    }

    const lineRows: Record<string, unknown>[] = [];
    for (let di = 0; di < program.days.length; di++) {
      const dayId = programDayId(program.id, di);
      const d = program.days[di]!;
      d.exercises.forEach((ex, ei) => {
        const nk = normNameKey(ex.name);
        lineRows.push({
          program_day_id: dayId,
          exercise_id: exerciseIdFromKey(nk),
          sort_order: ei,
          max_weight: ex.maxWeight,
          target_sets: ex.targetSets,
          superset_group: ex.supersetGroup,
          is_amrap: ex.isAmrap,
          is_warmup: ex.isWarmup,
          notes: ex.notes,
        });
      });
    }

    if (lineRows.length > 0) {
      const insLines = await restFetchServiceRole("catalog_day_exercises", {
        method: "POST",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify(lineRows),
      });
      if (!insLines.ok) {
        const text = await insLines.text();
        throw new HttpError(
          502,
          `catalog_day_exercises insert failed: ${insLines.status} ${text.slice(0, 200)}`
        );
      }
    }

    const rel = await restJsonServiceRole<{ version: number }[]>(
      "catalog_release",
      "GET",
      undefined,
      "select=version&id=eq.1"
    );
    const prev = rel[0]?.version;
    const nextVersion = typeof prev === "number" && Number.isFinite(prev) ? prev + 1 : 1;

    await restJsonServiceRole(
      "catalog_release",
      "PATCH",
      {
        version: nextVersion,
        notes: `publish:${program.id}`,
        published_at: new Date().toISOString(),
      },
      "id=eq.1"
    );

    res.json({ ok: true, programId: program.id, catalogVersion: nextVersion });
  } catch (e) {
    next(e);
  }
}
