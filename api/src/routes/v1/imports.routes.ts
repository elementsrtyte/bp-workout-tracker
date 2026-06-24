import { type NextFunction, type Request, type Response, Router } from "express";
import { HttpError } from "../../lib/http-error.js";
import { requireAuth } from "../../middleware/auth.js";
import { programImportBodyParser } from "../../middleware/program-import-body.js";
import {
  importProgramFromPlainText,
  type ProgramImportKind,
} from "../../services/openai.js";

function parseImportKind(raw: unknown): ProgramImportKind {
  const s = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  if (s === "workout_log" || s === "workoutlog") return "workout_log";
  if (s === "program_day" || s === "programday") return "program_day";
  return "program";
}

function importOptionsFromRequest(req: Request): {
  kind: ProgramImportKind;
  targetProgramName?: string;
  targetDayLabel?: string;
  existingDaysSummary?: string;
} {
  const body = req.body;
  const b =
    body && typeof body === "object" && !Array.isArray(body) && !(body instanceof Buffer)
      ? (body as Record<string, unknown>)
      : {};
  const str = (key: string): string | undefined => {
    const v = b[key];
    if (typeof v !== "string") return undefined;
    const t = v.trim();
    return t.length > 0 ? t : undefined;
  };
  return {
    kind: parseImportKind(b.importKind),
    targetProgramName: str("targetProgramName"),
    targetDayLabel: str("targetDayLabel"),
    existingDaysSummary: str("existingDaysSummary"),
  };
}

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
    const opts = importOptionsFromRequest(req);
    const { program, historicalWorkouts } = await importProgramFromPlainText(text, opts);
    res.json({ program, historicalWorkouts });
  } catch (e) {
    next(e);
  }
}

export const importsRouter = Router();

importsRouter.post("/programs", requireAuth, programImportBodyParser, postProgramImport);
