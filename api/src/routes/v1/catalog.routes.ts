import { Router } from "express";
import { fetchWorkoutProgramsBundle } from "../../services/workout-catalog.js";

export const catalogRouter = Router();

catalogRouter.get("/programs", async (_req, res, next) => {
  try {
    const bundle = await fetchWorkoutProgramsBundle();
    res.json(bundle);
  } catch (e) {
    next(e);
  }
});
