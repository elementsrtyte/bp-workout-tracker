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

export function extractJsonObject(raw: string): unknown {
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
    const v = JSON.parse(trimmed.slice(start, end + 1));
    if (Array.isArray(v)) return v;
  }
  throw new HttpError(502, "Model did not return valid JSON array");
}

export function sanitizeStringArray(arr: unknown[]): string[] {
  return arr
    .filter((x): x is string => typeof x === "string")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export const IMPORT_PROGRAM_SYSTEM_PROMPT = `You extract strength-training program structure AND any completed workout history from messy, noisy text (exports, notes, emails, spreadsheets pasted together, chat logs, OCR).

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

export function normalizeImportPayload(obj: unknown): { program: unknown; historicalWorkouts: unknown[] } {
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
export async function importProgramFromPlainText(
  trimmedText: string
): Promise<{ program: unknown; historicalWorkouts: unknown[] }> {
  if (!trimmedText) throw new HttpError(400, "text required");
  const userMsg = `Convert this workout text into JSON:\n\n${trimmedText}`;
  const raw = await chatComplete(IMPORT_PROGRAM_SYSTEM_PROMPT, userMsg, 12000);
  const parsed = extractJsonObject(raw);
  return normalizeImportPayload(parsed);
}
