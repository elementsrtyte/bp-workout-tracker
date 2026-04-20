import type { NextFunction, Request, Response } from "express";
import { HttpError } from "../lib/http-error.js";
import { restFetchServiceRole, restJsonServiceRole } from "../integrations/supabase.js";
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
    const safe = q.replaceAll("*", "").replaceAll(/[,()]/g, " ").trim();
    const search =
      safe.length > 0
        ? `select=id,name,name_key&or=(name.ilike.*${encodeURIComponent(safe)}*,name_key.ilike.*${encodeURIComponent(safe)}*)&order=name.asc&limit=${limit}`
        : `select=id,name,name_key&order=name.asc&limit=${limit}`;
    const rows = await restJsonServiceRole<{ id: string; name: string; name_key: string }[]>(
      "exercises",
      "GET",
      undefined,
      search
    );
    res.json({ exercises: rows });
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
    const [release, exerciseHead, programRows] = await Promise.all([
      restJsonServiceRole<{ id: number; version: number; notes: string | null }[]>(
        "catalog_release",
        "GET",
        undefined,
        "select=*"
      ),
      restFetchServiceRole("exercises", {
        method: "GET",
        search: "select=id&limit=1",
        headers: { Prefer: "count=exact" },
      }),
      restJsonServiceRole<{ id: string; name: string }[]>(
        "catalog_programs",
        "GET",
        undefined,
        "select=id,name&order=name.asc"
      ),
    ]);
    const countHeader = exerciseHead.headers.get("content-range");
    let exerciseCount = 0;
    if (countHeader) {
      const m = /\/(\d+)$/.exec(countHeader);
      if (m) exerciseCount = parseInt(m[1], 10);
    }
    res.json({
      catalog_release: release[0] ?? null,
      exerciseCount,
      programs: programRows,
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
    const rows = await restJsonServiceRole<
      { id: number; payload: unknown; updated_at: string }[]
    >("bundled_progress_reference", "GET", undefined, "select=*");
    res.json({ bundled_progress: rows[0] ?? null });
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
    await restJsonServiceRole<unknown>(
      "bundled_progress_reference",
      "PATCH",
      { payload: body.payload, updated_at: new Date().toISOString() },
      "id=eq.1"
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
      const prof = await restJsonServiceRole<ProfileRow[]>(
        "profiles",
        "GET",
        undefined,
        `select=id,email,display_name&email=ilike.*${encodeURIComponent(email)}*&limit=5`
      );
      if (prof.length === 0) {
        res.json({ workouts: [], total: 0, profilesByUserId: {} });
        return;
      }
      if (filterUserId && !prof.some((p) => p.id === filterUserId)) {
        res.json({ workouts: [], total: 0, profilesByUserId: {} });
        return;
      }
      if (!filterUserId) filterUserId = prof[0]!.id;
    }

    let anomalyIds: string[] | null = null;
    if (anomalyOnly) {
      const rows = await restJsonServiceRole<{ workout_id: string }[]>(
        "admin_workouts_with_anomalies",
        "GET",
        undefined,
        "select=workout_id"
      );
      anomalyIds = [...new Set(rows.map((r) => r.workout_id))];
      assertInListSize("Anomaly", anomalyIds);
      if (anomalyIds.length === 0) {
        res.json({ workouts: [], total: 0, profilesByUserId: {} });
        return;
      }
    }

    let unlinkedWorkoutIds: string[] | null = null;
    if (unlinkedOnly) {
      const exRows = await restJsonServiceRole<{ workout_id: string }[]>(
        "workout_exercises",
        "GET",
        undefined,
        "select=workout_id&canonical_exercise_id=is.null&limit=5000"
      );
      unlinkedWorkoutIds = [...new Set(exRows.map((r) => r.workout_id))];
      assertInListSize("Unlinked exercise", unlinkedWorkoutIds);
      if (unlinkedWorkoutIds.length === 0) {
        res.json({ workouts: [], total: 0, profilesByUserId: {} });
        return;
      }
    }

    const conditions: string[] = [];
    if (filterUserId) conditions.push(`user_id=eq.${filterUserId}`);
    if (programId) conditions.push(`program_id=eq.${encodeURIComponent(programId)}`);
    if (anomalyIds) {
      conditions.push(`id=in.(${anomalyIds.join(",")})`);
    }
    if (unlinkedWorkoutIds) {
      conditions.push(`id=in.(${unlinkedWorkoutIds.join(",")})`);
    }

    const andFilter = conditions.length > 0 ? `&${conditions.join("&")}` : "";
    const search = `select=*&order=logged_at.desc&limit=${limit}&offset=${offset}${andFilter}`;
    const workouts = await restJsonServiceRole<WorkoutRow[]>("workouts", "GET", undefined, search);

    const countSearch = `select=id&limit=1${andFilter}`;
    const countRes = await restFetchServiceRole("workouts", {
      method: "GET",
      search: countSearch,
      headers: { Prefer: "count=exact" },
    });
    let total = workouts.length;
    const cr = countRes.headers.get("content-range");
    if (cr) {
      const m = /\/(\d+)$/.exec(cr);
      if (m) total = parseInt(m[1], 10);
    }

    const userIds = [...new Set(workouts.map((w) => w.user_id))];
    let profilesByUserId: Record<string, ProfileRow> = {};
    if (userIds.length > 0) {
      const plist = await restJsonServiceRole<ProfileRow[]>(
        "profiles",
        "GET",
        undefined,
        `select=id,email,display_name&id=in.(${userIds.join(",")})`
      );
      profilesByUserId = Object.fromEntries(plist.map((p) => [p.id, p]));
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

    const wrows = await restJsonServiceRole<WorkoutRow[]>(
      "workouts",
      "GET",
      undefined,
      `select=*&id=eq.${encodeURIComponent(id)}&limit=1`
    );
    const workout = wrows[0];
    if (!workout) throw new HttpError(404, "Workout not found");

    // Embed sets via FK (workout_sets.exercise_id → workout_exercises.id). A separate
    // `exercise_id=in.(...)` query can return no rows in some PostgREST/URL edge cases.
    const exercisesRaw = await restJsonServiceRole<
      {
        id: string;
        name: string;
        prescribed_name: string | null;
        sort_order: number;
        canonical_exercise_id: string | null;
        workout_sets: Array<{
          id: string;
          weight: number;
          reps: number;
          sort_order: number;
        }> | null;
      }[]
    >(
      "workout_exercises",
      "GET",
      undefined,
      `workout_id=eq.${encodeURIComponent(id)}&select=id,name,prescribed_name,sort_order,canonical_exercise_id,workout_sets(id,weight,reps,sort_order)&order=sort_order.asc`
    );

    const exercises = exercisesRaw.map((e) => ({
      id: e.id,
      name: e.name,
      prescribed_name: e.prescribed_name,
      sort_order: e.sort_order,
      canonical_exercise_id: e.canonical_exercise_id,
      workout_sets: [...(e.workout_sets ?? [])].sort((a, b) => a.sort_order - b.sort_order),
    }));

    const prof = await restJsonServiceRole<ProfileRow[]>(
      "profiles",
      "GET",
      undefined,
      `id=eq.${workout.user_id}&select=id,email,display_name&limit=1`
    );

    res.json({
      workout,
      exercises,
      profile: prof[0] ?? null,
    });
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
    const patch: Record<string, unknown> = {};
    if (typeof body.notes === "string") patch.notes = body.notes;
    if (typeof body.program_name === "string") patch.program_name = body.program_name;
    if (typeof body.day_label === "string") patch.day_label = body.day_label;
    if (Object.keys(patch).length === 0) throw new HttpError(400, "No valid fields to patch");
    patch.updated_at = new Date().toISOString();

    await restJsonServiceRole<unknown>("workouts", "PATCH", patch, `id=eq.${id}`);
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
    const r = await restFetchServiceRole("workouts", { method: "DELETE", search: `id=eq.${id}` });
    if (!r.ok) {
      const t = await r.text();
      throw new HttpError(502, `Delete failed: ${r.status} ${t.slice(0, 200)}`);
    }
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
    const patch: Record<string, unknown> = {};
    if (body.canonical_exercise_id === null) {
      patch.canonical_exercise_id = null;
    } else if (typeof body.canonical_exercise_id === "string" && body.canonical_exercise_id.trim()) {
      patch.canonical_exercise_id = body.canonical_exercise_id.trim();
    }
    if (typeof body.name === "string") patch.name = body.name;
    if (body.prescribed_name === null) {
      patch.prescribed_name = null;
    } else if (typeof body.prescribed_name === "string") {
      patch.prescribed_name = body.prescribed_name;
    }
    if (Object.keys(patch).length === 0) throw new HttpError(400, "No valid fields to patch");

    await restJsonServiceRole<unknown>("workout_exercises", "PATCH", patch, `id=eq.${id}`);
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

    const existing = await restJsonServiceRole<{ id: string }[]>(
      "catalog_programs",
      "GET",
      undefined,
      `select=id&id=eq.${encodeURIComponent(programId)}&limit=1`
    );
    if (existing.length === 0) throw new HttpError(404, "Catalog program not found");

    const del = await restFetchServiceRole("catalog_programs", {
      method: "DELETE",
      search: `id=eq.${encodeURIComponent(programId)}`,
    });
    if (!del.ok) {
      const t = await del.text();
      throw new HttpError(502, `Delete catalog program failed: ${del.status} ${t.slice(0, 200)}`);
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
        notes: `delete:${programId}`,
        published_at: new Date().toISOString(),
      },
      "id=eq.1"
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

    const exCheck = await restJsonServiceRole<{ id: string }[]>(
      "exercises",
      "GET",
      undefined,
      `id=eq.${canonicalExerciseId}&select=id&limit=1`
    );
    if (exCheck.length === 0) throw new HttpError(400, "canonicalExerciseId not found");

    const candidates = await restJsonServiceRole<{ id: string; name: string }[]>(
      "workout_exercises",
      "GET",
      undefined,
      "select=id,name&canonical_exercise_id=is.null&limit=5000"
    );
    const key = normNameKey(nameKey);
    const ids = candidates.filter((c) => normNameKey(c.name) === key).map((c) => c.id);
    if (dryRun) {
      res.json({ dryRun: true, matchCount: ids.length, ids: ids.slice(0, 50) });
      return;
    }
    const chunk = 80;
    for (let i = 0; i < ids.length; i += chunk) {
      const slice = ids.slice(i, i + chunk);
      if (slice.length === 0) continue;
      await restJsonServiceRole<unknown>(
        "workout_exercises",
        "PATCH",
        { canonical_exercise_id: canonicalExerciseId },
        `id=in.(${slice.join(",")})`
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
