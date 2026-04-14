import { type NextFunction, type Request, type Response, Router } from "express";
import { HttpError } from "../../lib/http-error.js";
import { requireAuth } from "../../middleware/auth.js";
import { programImportBodyParser } from "../../middleware/program-import-body.js";
import { importProgramFromPlainText } from "../../services/openai.js";

async function postProgramImport(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const ct = (req.headers["content-type"] ?? "").toLowerCase();
    let text: string;
    if (ct.includes("multipart/form-data")) {
      const f = req.file;
      if (!f?.buffer?.length) {
        throw new HttpError(400, 'multipart field "file" with workout text is required');
      }
      text = f.buffer.toString("utf8");
    } else if (ct.includes("application/json")) {
      text = ((req.body as { text?: string })?.text ?? "").trim();
    } else {
      text = typeof req.body === "string" ? req.body.trim() : "";
    }
    const { program, historicalWorkouts } = await importProgramFromPlainText(text);
    res.json({ program, historicalWorkouts });
  } catch (e) {
    next(e);
  }
}

export const importsRouter = Router();

importsRouter.post("/programs", requireAuth, programImportBodyParser, postProgramImport);
