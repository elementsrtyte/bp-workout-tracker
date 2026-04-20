import { Router } from "express";
import { requirePlatformAdmin } from "../../middleware/platform-admin.js";
import {
  deleteAdminCatalogProgram,
  deleteAdminWorkout,
  getAdminCatalogSnapshot,
  getAdminExercises,
  getAdminWorkoutDetail,
  getBundledProgress,
  listAdminWorkouts,
  patchAdminWorkout,
  patchAdminWorkoutExercise,
  patchBundledProgress,
  postBulkLinkWorkoutExercises,
} from "../../services/admin-seed-and-workouts.js";
import { postPublishCatalogProgram } from "../../services/catalog-publish.js";

export const adminRouter = Router();

adminRouter.use(requirePlatformAdmin);

adminRouter.post("/catalog/programs", postPublishCatalogProgram);
adminRouter.delete("/catalog/programs/:programId", deleteAdminCatalogProgram);

adminRouter.get("/catalog/snapshot", getAdminCatalogSnapshot);
adminRouter.get("/exercises", getAdminExercises);
adminRouter.get("/bundled-progress", getBundledProgress);
adminRouter.patch("/bundled-progress", patchBundledProgress);

adminRouter.get("/workouts", listAdminWorkouts);
adminRouter.get("/workouts/:id", getAdminWorkoutDetail);
adminRouter.patch("/workouts/:id", patchAdminWorkout);
adminRouter.delete("/workouts/:id", deleteAdminWorkout);
adminRouter.patch("/workout-exercises/:id", patchAdminWorkoutExercise);
adminRouter.post("/workout-exercises/bulk-link", postBulkLinkWorkoutExercises);
