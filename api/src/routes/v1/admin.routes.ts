import { Router } from "express";
import { requireAuth } from "../../middleware/auth.js";
import { postPublishCatalogProgram } from "../../services/catalog-publish.js";

export const adminRouter = Router();

adminRouter.use(requireAuth);
adminRouter.post("/catalog/programs", postPublishCatalogProgram);
