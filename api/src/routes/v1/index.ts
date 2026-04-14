import { Router } from "express";
import { adminRouter } from "./admin.routes.js";
import { catalogRouter } from "./catalog.routes.js";
import { exercisesRouter } from "./exercises.routes.js";
import { importsRouter } from "./imports.routes.js";
import { getApiRoot } from "./meta.js";
import { workoutsRouter } from "./workouts.routes.js";

export function createV1Router(): Router {
  const v1 = Router();

  v1.get("/", getApiRoot);
  v1.use("/catalog", catalogRouter);
  v1.use("/workouts", workoutsRouter);
  v1.use("/exercises", exercisesRouter);
  v1.use("/imports", importsRouter);
  v1.use("/admin", adminRouter);

  return v1;
}
