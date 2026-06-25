import type { NextFunction, Request, Response } from "express";
import { query, withTransaction } from "../db/pool.js";
import { HttpError } from "../lib/http-error.js";
import { logAdminAction } from "./platform-admin.js";
import type { AdminRequest } from "../middleware/platform-admin.js";

function normNameKey(name: string): string {
  return name.trim().toLowerCase();
}

function parseLimit(raw: unknown, fallback: number, max: number): number {
  const n = typeof raw === "string" ? parseInt(raw, 10) : typeof raw === "number" ? raw : NaN;
  if (!Number.isFinite(n) || n < 1) return fallback;
  return Math.min(max, n);
}

function parseOffset(raw: unknown): number {
  const n = typeof raw === "string" ? parseInt(raw, 10) : typeof raw === "number" ? raw : NaN;
  if (!Number.isFinite(n) || n < 0) return 0;
  return n;
}

const MAX_IN_LIST = 250;

function assertInListSize(label: string, ids: string[]): void {
  if (ids.length > MAX_IN_LIST) {
    throw new HttpError(
      400,
      `${label} matches ${ids.length} rows; narrow filters (max ${MAX_IN_LIST} for this endpoint).`
    );
  }
}

type WorkoutRow = {
  id: string;
  user_id: string;
  client_workout_id: string | null;
  logged_at: string;
  program_id: string | null;
  program_name: string | null;
  day_label: string | null;
  notes: string | null;
};

type ProfileRow = { id: string; email: string | null; display_name: string | null };

export async function getAdminExercises(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const q = typeof req.query.q === "string" ? req.query.q.trim() : "";
    const limit = parseLimit(req.query.limit, 40, 200);
    const pattern = q.length > 0 ? `%${q.replaceAll("%", "")}%` : null;
    const r = pattern
      ? await query<{ id: string; name: string; name_key: string }>(
          `SELECT id, name, name_key FROM exercises
           WHERE name ILIKE $1 OR name_key ILIKE $1
           ORDER BY name ASC LIMIT $2`,
          [pattern, limit]
        )
      : await query<{ id: string; name: string; name_key: string }>(
          `SELECT id, name, name_key FROM exercises ORDER BY name ASC LIMIT $1`,
          [limit]
        );
    res.json({ exercises: r.rows });
  } catch (e) {
    next(e);
  }
}

export async function getAdminCatalogSnapshot(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const [release, countRes, programsRes] = await Promise.all([
      query<{ id: number; version: number; notes: string | null }>(`SELECT * FROM catalog_release WHERE id = 1`),
      query<{ c: string }>(`SELECT count(*)::text AS c FROM exercises`),
      query<{ id: string; name: string }>(`SELECT id, name FROM catalog_programs ORDER BY name ASC`),
    ]);
    res.json({
      catalog_release: release.rows[0] ?? null,
      exerciseCount: parseInt(countRes.rows[0]?.c ?? "0", 10),
      programs: programsRes.rows,
    });
  } catch (e) {
    next(e);
  }
}

export async function getBundledProgress(
  _req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const r = await query<{ id: number; payload: unknown; updated_at: string }>(
      `SELECT id, payload, updated_at FROM bundled_progress_reference WHERE id = 1`
    );
    res.json({ bundled_progress: r.rows[0] ?? null });
  } catch (e) {
    next(e);
  }
}

export async function patchBundledProgress(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const admin = req as AdminRequest;
    const body = req.body as { payload?: unknown };
    if (body.payload === undefined || typeof body.payload !== "object" || body.payload === null) {
      throw new HttpError(400, "payload object required");
    }
    await query(
      `UPDATE bundled_progress_reference SET payload = $1::jsonb, updated_at = now() WHERE id = 1`,
      [JSON.stringify(body.payload)]
    );
    logAdminAction(admin.adminEmail, "patch_bundled_progress", {});
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
}

export async function listAdminWorkouts(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const limit = parseLimit(req.query.limit, 25, 100);
    const offset = parseOffset(req.query.offset);
    const userId = typeof req.query.userId === "string" ? req.query.userId.trim() : "";
    const email = typeof req.query.email === "string" ? req.query.email.trim().toLowerCase() : "";
    const programId = typeof req.query.programId === "string" ? req.query.programId.trim() : "";
    const anomalyOnly =
      req.query.anomaly === "1" || req.query.anomaly === "true" || req.query.anomalies === "1";
    const unlinkedOnly =
      req.query.unlinked === "1" ||
      req.query.unlinked === "true" ||
      req.query.hasUnlinked === "1";

    let filterUserId = userId;
    if (email.length > 0) {
      const prof = await query<ProfileRow>(
        `SELECT id, email, display_name FROM profiles WHERE lower(email) LIKE $1 LIMIT 5`,
        [`%${email}%`]
      );
      if (prof.rows.length === 0) {
        res.json({ workouts: [], total: 0, profilesByUserId: {} });
        return;
      }
      if (filterUserId && !prof.rows.some((p) => p.id === filterUserId)) {
        res.json({ workouts: [], total: 0, profilesByUserId: {} });
        return;
      }
      if (!filterUserId) filterUserId = prof.rows[0]!.id;
    }

    let anomalyIds: string[] | null = null;
    if (anomalyOnly) {
      const rows = await query<{ workout_id: string }>(
        `SELECT workout_id FROM admin_workouts_with_anomalies`
      );
      anomalyIds = [...new Set(rows.rows.map((r) => r.workout_id))];
      assertInListSize("Anomaly", anomalyIds);
      if (anomalyIds.length === 0) {
        res.json({ workouts: [], total: 0, profilesByUserId: {} });
        return;
      }
    }

    let unlinkedWorkoutIds: string[] | null = null;
    if (unlinkedOnly) {
      const exRows = await query<{ workout_id: string }>(
        `SELECT DISTINCT workout_id FROM workout_exercises WHERE canonical_exercise_id IS NULL LIMIT 5000`
      );
      unlinkedWorkoutIds = exRows.rows.map((r) => r.workout_id);
      assertInListSize("Unlinked exercise", unlinkedWorkoutIds);
      if (unlinkedWorkoutIds.length === 0) {
        res.json({ workouts: [], total: 0, profilesByUserId: {} });
        return;
      }
    }

    const conditions: string[] = [];
    const params: unknown[] = [];
    let pi = 1;

    if (filterUserId) {
      conditions.push(`user_id = $${pi++}`);
      params.push(filterUserId);
    }
    if (programId) {
      conditions.push(`program_id = $${pi++}`);
      params.push(programId);
    }
    if (anomalyIds) {
      conditions.push(`id = ANY($${pi++}::uuid[])`);
      params.push(anomalyIds);
    }
    if (unlinkedWorkoutIds) {
      conditions.push(`id = ANY($${pi++}::uuid[])`);
      params.push(unlinkedWorkoutIds);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
    const countR = await query<{ c: string }>(
      `SELECT count(*)::text AS c FROM workouts ${where}`,
      params
    );
    const total = parseInt(countR.rows[0]?.c ?? "0", 10);

    const listR = await query<WorkoutRow>(
      `SELECT * FROM workouts ${where} ORDER BY logged_at DESC LIMIT $${pi++} OFFSET $${pi}`,
      [...params, limit, offset]
    );
    const workouts = listR.rows;

    const userIds = [...new Set(workouts.map((w) => w.user_id))];
    let profilesByUserId: Record<string, ProfileRow> = {};
    if (userIds.length > 0) {
      const plist = await query<ProfileRow>(
        `SELECT id, email, display_name FROM profiles WHERE id = ANY($1::uuid[])`,
        [userIds]
      );
      profilesByUserId = Object.fromEntries(plist.rows.map((p) => [p.id, p]));
    }

    res.json({ workouts, total, profilesByUserId });
  } catch (e) {
    next(e);
  }
}

export async function getAdminWorkoutDetail(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const id = req.params.id?.trim();
    if (!id) throw new HttpError(400, "workout id required");

    const wrows = await query<WorkoutRow>(`SELECT * FROM workouts WHERE id = $1 LIMIT 1`, [id]);
    const workout = wrows.rows[0];
    if (!workout) throw new HttpError(404, "Workout not found");

    const exRows = await query<{
      id: string;
      name: string;
      prescribed_name: string | null;
      sort_order: number;
      canonical_exercise_id: string | null;
    }>(
      `SELECT id, name, prescribed_name, sort_order, canonical_exercise_id
       FROM workout_exercises WHERE workout_id = $1 ORDER BY sort_order ASC`,
      [id]
    );

    const exercises = [];
    for (const e of exRows.rows) {
      const setsR = await query<{ id: string; weight: number; reps: number; sort_order: number }>(
        `SELECT id, weight, reps, sort_order FROM workout_sets WHERE exercise_id = $1 ORDER BY sort_order ASC`,
        [e.id]
      );
      exercises.push({ ...e, workout_sets: setsR.rows });
    }

    const prof = await query<ProfileRow>(
      `SELECT id, email, display_name FROM profiles WHERE id = $1 LIMIT 1`,
      [workout.user_id]
    );

    res.json({ workout, exercises, profile: prof.rows[0] ?? null });
  } catch (e) {
    next(e);
  }
}

export async function patchAdminWorkout(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const admin = req as AdminRequest;
    const id = req.params.id?.trim();
    if (!id) throw new HttpError(400, "workout id required");
    const body = req.body as { notes?: unknown; program_name?: unknown; day_label?: unknown };
    const sets: string[] = [];
    const params: unknown[] = [];
    let pi = 1;
    if (typeof body.notes === "string") {
      sets.push(`notes = $${pi++}`);
      params.push(body.notes);
    }
    if (typeof body.program_name === "string") {
      sets.push(`program_name = $${pi++}`);
      params.push(body.program_name);
    }
    if (typeof body.day_label === "string") {
      sets.push(`day_label = $${pi++}`);
      params.push(body.day_label);
    }
    if (sets.length === 0) throw new HttpError(400, "No valid fields to patch");
    params.push(id);
    await query(`UPDATE workouts SET ${sets.join(", ")} WHERE id = $${pi}`, params);
    logAdminAction(admin.adminEmail, "patch_workout", { workout_id: id });
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
}

export async function deleteAdminWorkout(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const admin = req as AdminRequest;
    const id = req.params.id?.trim();
    if (!id) throw new HttpError(400, "workout id required");
    const r = await query(`DELETE FROM workouts WHERE id = $1`, [id]);
    if ((r.rowCount ?? 0) === 0) throw new HttpError(404, "Workout not found");
    logAdminAction(admin.adminEmail, "delete_workout", { workout_id: id });
    res.status(204).end();
  } catch (e) {
    next(e);
  }
}

export async function patchAdminWorkoutExercise(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const admin = req as AdminRequest;
    const id = req.params.id?.trim();
    if (!id) throw new HttpError(400, "workout exercise id required");
    const body = req.body as {
      canonical_exercise_id?: unknown;
      name?: unknown;
      prescribed_name?: unknown;
    };
    const sets: string[] = [];
    const params: unknown[] = [];
    let pi = 1;
    if (body.canonical_exercise_id === null) {
      sets.push(`canonical_exercise_id = NULL`);
    } else if (typeof body.canonical_exercise_id === "string" && body.canonical_exercise_id.trim()) {
      sets.push(`canonical_exercise_id = $${pi++}`);
      params.push(body.canonical_exercise_id.trim());
    }
    if (typeof body.name === "string") {
      sets.push(`name = $${pi++}`);
      params.push(body.name);
    }
    if (body.prescribed_name === null) {
      sets.push(`prescribed_name = NULL`);
    } else if (typeof body.prescribed_name === "string") {
      sets.push(`prescribed_name = $${pi++}`);
      params.push(body.prescribed_name);
    }
    if (sets.length === 0) throw new HttpError(400, "No valid fields to patch");
    params.push(id);
    await query(`UPDATE workout_exercises SET ${sets.join(", ")} WHERE id = $${pi}`, params);
    logAdminAction(admin.adminEmail, "patch_workout_exercise", { workout_exercise_id: id });
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
}

export async function deleteAdminCatalogProgram(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const admin = req as AdminRequest;
    const programId = req.params.programId?.trim();
    if (!programId) throw new HttpError(400, "program id required");
    if (programId.length > 200) throw new HttpError(400, "program id too long");

    const existing = await query<{ id: string }>(
      `SELECT id FROM catalog_programs WHERE id = $1 LIMIT 1`,
      [programId]
    );
    if (existing.rows.length === 0) throw new HttpError(404, "Catalog program not found");

    await query(`DELETE FROM catalog_programs WHERE id = $1`, [programId]);

    const rel = await query<{ version: number }>(`SELECT version FROM catalog_release WHERE id = 1`);
    const prev = rel.rows[0]?.version;
    const nextVersion = typeof prev === "number" && Number.isFinite(prev) ? prev + 1 : 1;
    await query(
      `UPDATE catalog_release SET version = $1, notes = $2, published_at = now() WHERE id = 1`,
      [nextVersion, `delete:${programId}`]
    );

    logAdminAction(admin.adminEmail, "delete_catalog_program", { programId });
    res.json({ ok: true, programId, catalogVersion: nextVersion });
  } catch (e) {
    next(e);
  }
}

export async function postBulkLinkWorkoutExercises(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const admin = req as AdminRequest;
    const body = req.body as {
      nameKey?: unknown;
      canonicalExerciseId?: unknown;
      dryRun?: unknown;
    };
    const nameKey = typeof body.nameKey === "string" ? body.nameKey.trim() : "";
    const canonicalExerciseId =
      typeof body.canonicalExerciseId === "string" ? body.canonicalExerciseId.trim() : "";
    const dryRun = body.dryRun === true;
    if (!nameKey) throw new HttpError(400, "nameKey required");
    if (!canonicalExerciseId) throw new HttpError(400, "canonicalExerciseId required");

    const exCheck = await query<{ id: string }>(
      `SELECT id FROM exercises WHERE id = $1 LIMIT 1`,
      [canonicalExerciseId]
    );
    if (exCheck.rows.length === 0) throw new HttpError(400, "canonicalExerciseId not found");

    const candidates = await query<{ id: string; name: string }>(
      `SELECT id, name FROM workout_exercises WHERE canonical_exercise_id IS NULL LIMIT 5000`
    );
    const key = normNameKey(nameKey);
    const ids = candidates.rows.filter((c) => normNameKey(c.name) === key).map((c) => c.id);
    if (dryRun) {
      res.json({ dryRun: true, matchCount: ids.length, ids: ids.slice(0, 50) });
      return;
    }
    if (ids.length > 0) {
      await query(
        `UPDATE workout_exercises SET canonical_exercise_id = $1 WHERE id = ANY($2::uuid[])`,
        [canonicalExerciseId, ids]
      );
    }
    logAdminAction(admin.adminEmail, "bulk_link_workout_exercises", {
      nameKey: key,
      canonicalExerciseId,
      updated: ids.length,
    });
    res.json({ ok: true, updated: ids.length });
  } catch (e) {
    next(e);
  }
}
