import type { NextFunction, Request, Response } from "express";
import { HttpError } from "./httpError.js";
import { fetchSupabaseAuthUser, restFetch } from "./supabaseData.js";

type SyncSet = {
  id: string;
  weight: number;
  reps: number;
  order: number;
};

type SyncExercise = {
  id: string;
  name: string;
  prescribedName?: string | null;
  sortOrder: number;
  sets: SyncSet[];
};

type SyncBody = {
  id?: string;
  date?: string;
  programId?: string | null;
  programName?: string | null;
  dayLabel?: string | null;
  notes?: string | null;
  exercises?: SyncExercise[];
};

const uuidRe =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function assertUuid(label: string, v: string): void {
  if (!uuidRe.test(v)) throw new HttpError(400, `Invalid ${label}`);
}

type WorkoutRow = { id: string };

async function assertRestOk(res: globalThis.Response, ctx: string): Promise<void> {
  if (res.ok) return;
  const text = await res.text();
  throw new HttpError(502, `${ctx}: ${res.status} ${text.slice(0, 200)}`);
}

export async function postWorkoutSync(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const authHeader = req.header("authorization") ?? req.header("Authorization");
    const { id: userId } = await fetchSupabaseAuthUser(authHeader);
    const token = authHeader!.slice(7).trim();

    const body = req.body as SyncBody;
    const clientWorkoutId = body.id?.trim();
    const loggedAt = body.date?.trim();
    if (!clientWorkoutId || !loggedAt) {
      throw new HttpError(400, "id and date are required");
    }
    assertUuid("workout id", clientWorkoutId);

    const exercisesRaw = body.exercises;
    if (!Array.isArray(exercisesRaw)) {
      throw new HttpError(400, "exercises must be an array");
    }

    for (const ex of exercisesRaw) {
      assertUuid("exercise id", ex.id);
      if (typeof ex.name !== "string" || !ex.name.trim()) {
        throw new HttpError(400, "Each exercise needs a name");
      }
      if (typeof ex.sortOrder !== "number") throw new HttpError(400, "exercise sortOrder invalid");
      if (!Array.isArray(ex.sets)) throw new HttpError(400, "exercise sets must be an array");
      for (const s of ex.sets) {
        assertUuid("set id", s.id);
        if (typeof s.weight !== "number" || typeof s.reps !== "number" || typeof s.order !== "number") {
          throw new HttpError(400, "set weight, reps, order must be numbers");
        }
      }
    }

    const sortedEx = [...exercisesRaw].sort((a, b) => a.sortOrder - b.sortOrder);

    const workoutInsert = {
      user_id: userId,
      client_workout_id: clientWorkoutId,
      logged_at: loggedAt,
      program_id: body.programId ?? null,
      program_name: body.programName ?? null,
      day_label: body.dayLabel ?? null,
      notes: body.notes ?? null,
    };

    const patch = {
      logged_at: loggedAt,
      program_id: body.programId ?? null,
      program_name: body.programName ?? null,
      day_label: body.dayLabel ?? null,
      notes: body.notes ?? null,
    };

    let serverWorkoutId = await fetchWorkoutServerId(token, userId, clientWorkoutId);

    if (serverWorkoutId) {
      const patchR = await restFetch("workouts", token, {
        method: "PATCH",
        search: `id=eq.${serverWorkoutId}`,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(patch),
      });
      await assertRestOk(patchR, "PATCH workout");
    } else {
      const postR = await restFetch("workouts", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify(workoutInsert),
      });
      if (!postR.ok) {
        serverWorkoutId = await fetchWorkoutServerId(token, userId, clientWorkoutId);
        if (serverWorkoutId) {
          const patchR = await restFetch("workouts", token, {
            method: "PATCH",
            search: `id=eq.${serverWorkoutId}`,
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(patch),
          });
          await assertRestOk(patchR, "PATCH workout after conflict");
        } else {
          const text = await postR.text();
          throw new HttpError(502, `POST workout: ${postR.status} ${text.slice(0, 200)}`);
        }
      } else {
        const rows = (await postR.json()) as WorkoutRow[];
        const id = rows[0]?.id;
        if (!id) throw new HttpError(502, "No workout id returned");
        serverWorkoutId = id;
      }
    }

    const delR = await restFetch("workout_exercises", token, {
      method: "DELETE",
      search: `workout_id=eq.${serverWorkoutId}`,
    });
    await assertRestOk(delR, "DELETE workout_exercises");

    if (sortedEx.length === 0) {
      res.status(204).end();
      return;
    }

    const exerciseRows = sortedEx.map((ex) => ({
      workout_id: serverWorkoutId,
      client_exercise_id: ex.id,
      name: ex.name,
      prescribed_name: ex.prescribedName ?? null,
      sort_order: ex.sortOrder,
    }));

    const exPost = await restFetch("workout_exercises", token, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify(exerciseRows),
    });
    if (!exPost.ok) {
      const text = await exPost.text();
      throw new HttpError(502, `POST workout_exercises: ${exPost.status} ${text.slice(0, 200)}`);
    }
    const insertedEx = (await exPost.json()) as Array<{ id: string; client_exercise_id: string | null }>;

    const serverExerciseByClient = new Map<string, string>();
    for (const row of insertedEx) {
      if (row.client_exercise_id) {
        serverExerciseByClient.set(row.client_exercise_id, row.id);
      }
    }

    const setRows: Array<{
      exercise_id: string;
      client_set_id: string;
      weight: number;
      reps: number;
      sort_order: number;
    }> = [];

    for (const ex of sortedEx) {
      const sid = serverExerciseByClient.get(ex.id);
      if (!sid) continue;
      const sortedSets = [...ex.sets].sort((a, b) => a.order - b.order);
      for (const s of sortedSets) {
        setRows.push({
          exercise_id: sid,
          client_set_id: s.id,
          weight: s.weight,
          reps: s.reps,
          sort_order: s.order,
        });
      }
    }

    if (setRows.length > 0) {
      const setPost = await restFetch("workout_sets", token, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Prefer: "return=representation",
        },
        body: JSON.stringify(setRows),
      });
      if (!setPost.ok) {
        const text = await setPost.text();
        throw new HttpError(502, `POST workout_sets: ${setPost.status} ${text.slice(0, 200)}`);
      }
    }

    res.status(204).end();
  } catch (e) {
    next(e);
  }
}

async function fetchWorkoutServerId(
  userJwt: string,
  userId: string,
  clientWorkoutId: string
): Promise<string | null> {
  const r = await restFetch("workouts", userJwt, {
    method: "GET",
    search: `user_id=eq.${userId}&client_workout_id=eq.${clientWorkoutId}&select=id&limit=1`,
  });
  if (!r.ok) return null;
  const rows = (await r.json()) as WorkoutRow[];
  return rows[0]?.id ?? null;
}
