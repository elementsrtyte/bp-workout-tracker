import cors from "cors";
import express, { type NextFunction, type Request, type Response } from "express";
import multer, { type MulterError } from "multer";
import OpenAI from "openai";
import { HttpError } from "./httpError.js";
import { fetchSupabaseAuthUser } from "./supabaseData.js";
import { fetchWorkoutProgramsBundle } from "./workoutCatalog.js";
import { postWorkoutSync } from "./workoutSync.js";

const app = express();
app.use(cors({ origin: "*" }));
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

function requireEnv(name: string): string {
  const v = process.env[name]?.trim();
  if (!v) throw new Error(`Missing required env: ${name}`);
  return v;
}

async function verifySupabaseUser(authorization: string | undefined): Promise<void> {
  await fetchSupabaseAuthUser(authorization);
}

function openai(): OpenAI {
  return new OpenAI({ apiKey: requireEnv("OPENAI_API_KEY") });
}

async function chatComplete(
  system: string,
  user: string,
  maxTokens: number,
  model = "gpt-4o-mini"
): Promise<string> {
  const client = openai();
  const res = await client.chat.completions.create({
    model,
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
    max_tokens: maxTokens,
  });
  const text = res.choices[0]?.message?.content?.trim();
  if (!text) throw new HttpError(502, "No content from model");
  return text;
}

function extractJsonObject(raw: string): unknown {
  const trimmed = raw.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return JSON.parse(trimmed.slice(start, end + 1));
    }
  }
  throw new HttpError(502, "Model did not return valid JSON object");
}

function extractJsonArray(raw: string): unknown[] {
  const trimmed = raw.trim();
  try {
    const v = JSON.parse(trimmed);
    if (Array.isArray(v)) return v;
  } catch {
    /* fall through */
  }
  const start = trimmed.indexOf("[");
  const end = trimmed.lastIndexOf("]");
  if (start >= 0 && end > start) {
    const v = JSON.parse(trimmed.slice(start, end + 1));
    if (Array.isArray(v)) return v;
  }
  throw new HttpError(502, "Model did not return valid JSON array");
}

function sanitizeStringArray(arr: unknown[]): string[] {
  return arr
    .filter((x): x is string => typeof x === "string")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

const IMPORT_PROGRAM_SYSTEM_PROMPT = `You extract strength-training program structure AND any completed workout history from messy, noisy text (exports, notes, emails, spreadsheets pasted together, chat logs, OCR).

Reply with ONLY one JSON object (no markdown fences, no commentary). Required top-level shape:
{
  "program": {
    "name": "short title — infer from headings; if unknown use Imported program",
    "subtitle": "optional one-line summary or empty string",
    "days": [ /* see below */ ]
  },
  "historicalWorkouts": [ /* optional; see below */ ]
}

program.days — training template (the plan the athlete follows):
- One object per training day (Day 1, Push/Pull, Mon, A/B, etc.).
- exercises[]: name (required), maxWeight (string: e.g. "185 lb", "RPE 8", "%1RM", "BW" — use "" if unknown), targetSets (1–20, default 3), supersetGroup (same small int 1–6 for supersets, else null), isAmrap, isWarmup, notes.
- Infer structure from headings, bullets, tables, and repeated patterns. Ignore prose that is not exercise prescriptions.

historicalWorkouts — ONLY if the source contains dated (or clearly ordered) completed sessions with sets/reps/weights:
- Array of { "date": "YYYY-MM-DD" (ISO date; required for each row you include), "dayLabel": optional string matching a program day if known, "notes": optional, "exercises": [ { "name": string, "prescribedName": optional if a substitution, "sets": [ { "weight": number (0 for bodyweight/unknown load), "reps": positive int } ] } ] }
- Parse tables like "Bench135x8,8,6" into multiple sets. Convert kg/lb as numbers only (assume lb if unspecified unless context says kg).
- If the text has many sessions, include up to the 200 most recent / clearly dated ones; skip sessions you cannot date.
- If there is no logged history, use "historicalWorkouts": [].

Noise and robustness:
- Strip email footers, URLs, ads, signatures, "Sent from iPhone", thread headers, and unrelated chat.
- Prefer training content: exercise names, sets, reps, loads, dates, session labels.
- If the source is MOSTLY history with a weak template, still infer a reasonable program.days from the union of movements (split across days if week pattern is visible; otherwise one day is OK).
- Never invent dates; omit a session if you cannot assign YYYY-MM-DD.

Output valid JSON only.`;

function normalizeImportPayload(obj: unknown): { program: unknown; historicalWorkouts: unknown[] } {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) {
    throw new HttpError(502, "Model returned invalid import payload");
  }
  const o = obj as Record<string, unknown>;
  if (o.program && typeof o.program === "object" && !Array.isArray(o.program)) {
    const hist = o.historicalWorkouts;
    const historicalWorkouts = Array.isArray(hist) ? hist : [];
    return { program: o.program, historicalWorkouts };
  }
  if ("days" in o && Array.isArray((o as { days?: unknown }).days)) {
    return { program: o, historicalWorkouts: [] };
  }
  throw new HttpError(502, "Model JSON must include program with days, or legacy program shape");
}

/** LLM step shared by JSON, raw text body, and file upload import routes. */
async function importProgramFromPlainText(
  trimmedText: string
): Promise<{ program: unknown; historicalWorkouts: unknown[] }> {
  if (!trimmedText) throw new HttpError(400, "text required");
  const userMsg = `Convert this workout text into JSON:\n\n${trimmedText}`;
  const raw = await chatComplete(IMPORT_PROGRAM_SYSTEM_PROMPT, userMsg, 12000);
  const parsed = extractJsonObject(raw);
  return normalizeImportPayload(parsed);
}

async function requireAuth(req: Request, _res: Response, next: NextFunction): Promise<void> {
  try {
    await verifySupabaseUser(req.header("authorization") ?? req.header("Authorization"));
    next();
  } catch (e) {
    next(e);
  }
}

app.get("/v1/catalog/workout-programs", async (_req, res, next) => {
  try {
    const bundle = await fetchWorkoutProgramsBundle();
    res.json(bundle);
  } catch (e) {
    next(e);
  }
});

app.post("/v1/sync/workout", postWorkoutSync);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 2 * 1024 * 1024 },
});

const aiRouter = express.Router();
aiRouter.use(requireAuth);

aiRouter.post("/substitution-suggestions", async (req, res, next) => {
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
});

/** JSON body: `{ "text": "…" }` — same as pasting in the app. */
aiRouter.post("/import-program", async (req, res, next) => {
  try {
    const text = ((req.body as { text?: string })?.text ?? "").trim();
    const { program, historicalWorkouts } = await importProgramFromPlainText(text);
    res.json({ program, historicalWorkouts });
  } catch (e) {
    next(e);
  }
});

/** Raw body: entire workout as UTF-8 (e.g. `text/plain`; use `-H "Content-Type: text/plain"` with curl). */
aiRouter.post(
  "/import-program/raw",
  express.text({
    limit: "2mb",
    type: (req) => {
      const ct = (req.headers["content-type"] ?? "").toLowerCase();
      if (ct.includes("multipart")) return false;
      if (ct.includes("application/json")) return false;
      return true;
    },
  }),
  async (req, res, next) => {
    try {
      const rawBody = typeof req.body === "string" ? req.body : "";
      const { program, historicalWorkouts } = await importProgramFromPlainText(rawBody.trim());
      res.json({ program, historicalWorkouts });
    } catch (e) {
      next(e);
    }
  }
);

/** Multipart: field `file` — plain-text workout (.txt, notes export, etc.). */
aiRouter.post("/import-program/upload", upload.single("file"), async (req, res, next) => {
  try {
    const f = req.file;
    if (!f?.buffer?.length) {
      throw new HttpError(400, "multipart field \"file\" with workout text is required");
    }
    let text: string;
    try {
      text = f.buffer.toString("utf8");
    } catch {
      throw new HttpError(400, "Could not read file as UTF-8");
    }
    const { program, historicalWorkouts } = await importProgramFromPlainText(text.trim());
    res.json({ program, historicalWorkouts });
  } catch (e) {
    next(e);
  }
});

aiRouter.post("/related-exercises", async (req, res, next) => {
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
});

app.use("/v1/ai", aiRouter);

function isMulterError(e: unknown): e is MulterError {
  return typeof e === "object" && e !== null && "code" in e;
}

app.use((err: unknown, _req: Request, res: Response, _next: NextFunction) => {
  if (err instanceof HttpError) {
    res.status(err.status).json({ error: err.message });
    return;
  }
  if (isMulterError(err)) {
    const msg =
      err.code === "LIMIT_FILE_SIZE" ? "File too large (max 2MB)" : err.message;
    res.status(400).json({ error: msg });
    return;
  }
  console.error(err);
  res.status(500).json({ error: "Internal server error" });
});

const port = Number(process.env.PORT ?? "8787");
app.listen(port, "0.0.0.0", () => {
  console.log(`bp-workout-api (express) listening on http://127.0.0.1:${port}`);
});
