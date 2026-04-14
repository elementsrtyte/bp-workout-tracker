import { type NextFunction, type Request, type Response, Router } from "express";
import { HttpError } from "../../lib/http-error.js";
import { requireAuth } from "../../middleware/auth.js";
import { chatComplete, extractJsonArray, sanitizeStringArray } from "../../services/openai.js";

export const exercisesRouter = Router();
exercisesRouter.use(requireAuth);

async function postSubstitutionSuggestions(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  try {
    const body = req.body as { prescribedExercise?: string; userNote?: string | null };
    const prescribed = (body.prescribedExercise ?? "").trim();
    if (!prescribed) throw new HttpError(400, "prescribedExercise required");

    let note = "";
    const u = (body.userNote ?? "").trim();
    if (u) note = ` Gym context from the user: ${u}`;

    const system = `You help strength athletes substitute exercises when equipment is busy. Reply with ONLY valid JSON: an array of strings, each a concise exercise name (no numbering, no markdown). Prefer the same movement pattern and muscle emphasis. 5 to 10 items.`;
    const userMsg = `Prescribed exercise: ${prescribed}.${note}`;

    const raw = await chatComplete(system, userMsg, 400);
    const arr = extractJsonArray(raw);
    const suggestions = sanitizeStringArray(arr);
    res.json({ suggestions });
  } catch (e) {
    next(e);
  }
}

async function postRelatedExercises(req: Request, res: Response, next: NextFunction): Promise<void> {
  try {
    const body = req.body as {
      exerciseName?: string;
      allowedExactNames?: string[];
      limit?: number;
    };
    const ex = (body.exerciseName ?? "").trim();
    if (!ex) throw new HttpError(400, "exerciseName required");

    const allowedRaw = body.allowedExactNames ?? [];
    const allowed = [
      ...new Set(
        allowedRaw
          .map((s) => (typeof s === "string" ? s.trim() : ""))
          .filter((s) => s.length > 0)
      ),
    ].sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base" }));

    if (allowed.length === 0) {
      throw new HttpError(400, "allowedExactNames must be non-empty");
    }

    const limit = Math.min(12, Math.max(1, body.limit ?? 12));
    const allowedJSON = JSON.stringify(allowed);

    const system = `You help strength athletes find related exercises from a FIXED catalog only.
Reply with ONLY valid JSON: an array of strings. No markdown, no keys, no commentary.
Each string MUST be byte-for-byte identical to one of the strings in ALLOWED_EXERCISES (same spelling and punctuation). Do not invent names. Do not output anything outside that list.
Prefer 5 to ${limit} items: same movement pattern or muscle emphasis, common equipment swaps.
Exclude the current exercise if it appears in the list. Order most relevant first.`;

    const userMsg = `CURRENT_EXERCISE: ${ex}

ALLOWED_EXERCISES (JSON string array, you may ONLY choose from these):
${allowedJSON}`;

    const raw = await chatComplete(system, userMsg, 800);
    const arr = extractJsonArray(raw);
    const parsed = sanitizeStringArray(arr);
    const allowedLower = new Map(allowed.map((n) => [n.toLowerCase(), n]));
    const seen = new Set<string>();
    const out: string[] = [];
    for (const s of parsed) {
      if (s.toLowerCase() === ex.toLowerCase()) continue;
      const canon = allowedLower.get(s.toLowerCase());
      if (canon && !seen.has(canon)) {
        seen.add(canon);
        out.push(canon);
        if (out.length >= limit) break;
      }
    }
    res.json({ related: out });
  } catch (e) {
    next(e);
  }
}

exercisesRouter.post("/substitution-suggestions", postSubstitutionSuggestions);
exercisesRouter.post("/related", postRelatedExercises);
