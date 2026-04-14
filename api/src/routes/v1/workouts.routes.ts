import { Router } from "express";
import { requireAuth } from "../../middleware/auth.js";
import { postWorkoutSync } from "../../services/workout-sync.js";

export const workoutsRouter = Router();

workoutsRouter.post("/", requireAuth, postWorkoutSync);
