import type { NextFunction, Request, Response } from "express";
import { withTransaction } from "../db/pool.js";
import { HttpError } from "../lib/http-error.js";
import { verifyAuthUser } from "./auth-service.js";

type SyncSet = { id: string; weight: number; reps: number; order: number };

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

export async function postWorkoutSync(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const authHeader = req.header("authorization") ?? req.header("Authorization");
    const { id: userId } = await verifyAuthUser(authHeader);

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

    await withTransaction(async (client) => {
      const existing = await client.query<{ id: string }>(
        `SELECT id FROM workouts
         WHERE user_id = $1 AND client_workout_id = $2
         LIMIT 1`,
        [userId, clientWorkoutId]
      );
      let serverWorkoutId = existing.rows[0]?.id;

      if (serverWorkoutId) {
        await client.query(
          `UPDATE workouts SET
             logged_at = $2, program_id = $3, program_name = $4, day_label = $5, notes = $6
           WHERE id = $1 AND user_id = $7`,
          [
            serverWorkoutId,
            loggedAt,
            body.programId ?? null,
            body.programName ?? null,
            body.dayLabel ?? null,
            body.notes ?? null,
            userId,
          ]
        );
      } else {
        const ins = await client.query<{ id: string }>(
          `INSERT INTO workouts (user_id, client_workout_id, logged_at, program_id, program_name, day_label, notes)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           RETURNING id`,
          [
            userId,
            clientWorkoutId,
            loggedAt,
            body.programId ?? null,
            body.programName ?? null,
            body.dayLabel ?? null,
            body.notes ?? null,
          ]
        );
        serverWorkoutId = ins.rows[0]?.id;
        if (!serverWorkoutId) throw new HttpError(502, "Failed to create workout");
      }

      await client.query(`DELETE FROM workout_exercises WHERE workout_id = $1`, [serverWorkoutId]);

      if (sortedEx.length === 0) return;

      for (const ex of sortedEx) {
        const exIns = await client.query<{ id: string }>(
          `INSERT INTO workout_exercises (workout_id, client_exercise_id, name, prescribed_name, sort_order)
           VALUES ($1, $2, $3, $4, $5)
           RETURNING id`,
          [serverWorkoutId, ex.id, ex.name, ex.prescribedName ?? null, ex.sortOrder]
        );
        const exerciseId = exIns.rows[0]?.id;
        if (!exerciseId) continue;
        const sortedSets = [...ex.sets].sort((a, b) => a.order - b.order);
        for (const s of sortedSets) {
          await client.query(
            `INSERT INTO workout_sets (exercise_id, client_set_id, weight, reps, sort_order)
             VALUES ($1, $2, $3, $4, $5)`,
            [exerciseId, s.id, s.weight, s.reps, s.order]
          );
        }
      }
    });

    res.status(204).end();
  } catch (e) {
    next(e);
  }
}
