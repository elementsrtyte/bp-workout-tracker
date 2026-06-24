import OpenAI from "openai";
import { HttpError } from "../lib/http-error.js";

export function requireEnv(name: string): string {
  const v = process.env[name]?.trim();
  if (!v) throw new Error(`Missing required env: ${name}`);
  return v;
}

function openai(): OpenAI {
  return new OpenAI({ apiKey: requireEnv("OPENAI_API_KEY") });
}

export async function chatComplete(
  system: string,
  user: string,
  maxTokens: number,
  model = "gpt-4o-mini"
): Promise<string> {
  let client: OpenAI;
  try {
    client = openai();
  } catch (e) {
    if (e instanceof Error && e.message.includes("OPENAI_API_KEY")) {
      throw new HttpError(503, "AI is not configured on this server");
    }
    throw e;
  }
  try {
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
  } catch (e) {
    if (e instanceof HttpError) throw e;
    console.error("OpenAI chat.completions failed:", e);
    throw new HttpError(502, "AI service request failed");
  }
}

export function extractJsonObject(raw: string): unknown {
  const trimmed = raw.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const start = trimmed.indexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(trimmed.slice(start, end + 1));
      } catch {
        /* fall through */
      }
    }
  }
  throw new HttpError(502, "Model did not return valid JSON object");
}

export function extractJsonArray(raw: string): unknown[] {
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
    try {
      const v = JSON.parse(trimmed.slice(start, end + 1));
      if (Array.isArray(v)) return v;
    } catch {
      /* fall through */
    }
  }
  throw new HttpError(502, "Model did not return valid JSON array");
}

export function sanitizeStringArray(arr: unknown[]): string[] {
  return arr
    .filter((x): x is string => typeof x === "string")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export type ProgramImportKind = "program" | "workout_log" | "program_day";

export const IMPORT_PROGRAM_SYSTEM_PROMPT = `You extract strength-training program structure AND/OR completed workout history from messy, noisy text (exports, notes, emails, spreadsheets pasted together, chat logs, OCR).

The user message begins with an IMPORT MODE block — follow it strictly (what to prioritize, whether dates may be null, how many program.days to return).

Reply with ONLY one JSON object (no markdown fences, no commentary). Required top-level shape:
{
  "program": {
    "name": "short title — infer from headings; if unknown use Imported program",
    "subtitle": "optional one-line summary or empty string",
    "days": [ /* see below; may be [] when mode says so */ ]
  },
  "historicalWorkouts": [ /* see below */ ]
}

program.days — training template (the plan the athlete follows):
- One object per training day (Day 1, Push/Pull, Mon, A/B, etc.).
- exercises[]: name (required), maxWeight (string: e.g. "185 lb", "RPE 8", "%1RM", "BW" — use "" if unknown), targetSets (1–20, default 3), supersetGroup (same small int 1–6 for supersets, else null), isAmrap, isWarmup, notes.
- Infer structure from headings, bullets, tables, and repeated patterns. Ignore prose that is not exercise prescriptions.

historicalWorkouts — completed sessions with sets/reps/weights when the source describes logged work:
- Array of { "date": string or null, "dayLabel": optional string, "notes": optional, "exercises": [ { "name": string, "prescribedName": optional if a substitution, "sets": [ { "weight": number (0 for bodyweight/unknown load), "reps": positive int } ] } ] }
- When IMPORT MODE allows undated sessions: use "date": null for sessions with no explicit calendar date in the source (the app assigns placeholder dates). Preserve top-to-bottom / document order of sessions in the array.
- When the mode requires dates: use "date": "YYYY-MM-DD" only when the source clearly states a calendar date; otherwise omit that session or use null if the mode allows null.
- Parse tables like "Bench135x8,8,6" into multiple sets. Convert kg/lb as numbers only (assume lb if unspecified unless context says kg).
- Cap at 200 sessions; weaker / duplicate tail sessions may be dropped.

Noise and robustness:
- Strip email footers, URLs, ads, signatures, "Sent from iPhone", thread headers, and unrelated chat.
- Prefer training content: exercise names, sets, reps, loads, dates, session labels.
- If the source is MOSTLY history with a weak template, still infer a reasonable program.days from the union of movements when the mode asks for a program template (split across days if week pattern is visible; otherwise one day is OK).
- Do not invent specific calendar dates; use null for date when allowed and the text has no explicit date.

Output valid JSON only.`;

export function buildProgramImportUserMessage(
  trimmedText: string,
  kind: ProgramImportKind,
  ctx?: { targetProgramName?: string; targetDayLabel?: string; existingDaysSummary?: string }
): string {
  const lines: string[] = [];
  if (kind === "workout_log") {
    lines.push("IMPORT MODE: workout_log");
    lines.push(
      "Extract completed workout sessions into historicalWorkouts. Each session must include exercises with at least one set (weight + reps).",
      'Use "date": "YYYY-MM-DD" when the source clearly contains that calendar date.',
      'When there is no explicit calendar date for a session, still include the session with "date": null (preserve order from the source — first listed ≈ most recent).',
      'Set program.days to [] unless the same paste clearly describes a repeating week template you can infer.',
      ctx?.targetProgramName
        ? `Context: logs belong to program "${ctx.targetProgramName}".`
        : ""
    );
  } else if (kind === "program_day") {
    lines.push("IMPORT MODE: program_day");
    lines.push(
      "Extract exactly ONE new training day from the paste. Return program.days as an array with a single object (that day only).",
      "Use historicalWorkouts: [] unless the paste also contains clearly separable completed sessions with sets.",
      ctx?.targetProgramName ? `Program name: "${ctx.targetProgramName}".` : "",
      ctx?.targetDayLabel ? `Suggested day label (if it fits the text): "${ctx.targetDayLabel}".` : "",
      ctx?.existingDaysSummary
        ? `Existing program days (for naming consistency; do not duplicate a day label unless the user is replacing that day):\n${ctx.existingDaysSummary}`
        : ""
    );
  } else {
    lines.push("IMPORT MODE: program");
    lines.push(
      "Extract a full training program template in program.days and any optional dated or undated history in historicalWorkouts.",
      'For historicalWorkouts: use "YYYY-MM-DD" when the source states a date; use null for date when there is no explicit calendar date (preserve session order).'
    );
  }
  lines.push("", "Source text:", "", trimmedText);
  return lines.filter((s) => s.length > 0).join("\n");
}

export function normalizeImportPayload(obj: unknown): { program: unknown; historicalWorkouts: unknown[] } {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) {
    throw new HttpError(502, "Model returned invalid import payload");
  }
  const o = obj as Record<string, unknown>;
  if (o.program && typeof o.program === "object" && !Array.isArray(o.program)) {
    const prog = o.program as Record<string, unknown>;
    if (!Array.isArray(prog.days)) {
      prog.days = [];
    }
    const hist = o.historicalWorkouts;
    const historicalWorkouts = Array.isArray(hist) ? hist : [];
    return { program: prog, historicalWorkouts };
  }
  if ("days" in o && Array.isArray((o as { days?: unknown }).days)) {
    return { program: o, historicalWorkouts: [] };
  }
  throw new HttpError(502, "Model JSON must include program with days, or legacy program shape");
}

/** LLM step shared by JSON, raw text body, and file upload import routes. */
export async function importProgramFromPlainText(
  trimmedText: string,
  options?: {
    kind?: ProgramImportKind;
    targetProgramName?: string;
    targetDayLabel?: string;
    existingDaysSummary?: string;
  }
): Promise<{ program: unknown; historicalWorkouts: unknown[] }> {
  if (!trimmedText) throw new HttpError(400, "text required");
  const kind: ProgramImportKind =
    options?.kind === "workout_log" || options?.kind === "program_day" ? options.kind : "program";
  const userMsg = buildProgramImportUserMessage(trimmedText, kind, {
    targetProgramName: options?.targetProgramName,
    targetDayLabel: options?.targetDayLabel,
    existingDaysSummary: options?.existingDaysSummary,
  });
  const raw = await chatComplete(IMPORT_PROGRAM_SYSTEM_PROMPT, userMsg, 12000);
  const parsed = extractJsonObject(raw);
  return normalizeImportPayload(parsed);
}
