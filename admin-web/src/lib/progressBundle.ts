/** Mirrors iOS `ProgressModels.swift` — bundled reference progress JSON. */

export type ProgressEntry = {
  date: string;
  weight: number;
  reps: number;
  maxReps: number;
  program: string;
  dayTitle: string;
  substitutedPerformedAs?: string | null;
};

export type ExerciseProgress = {
  name: string;
  sessionCount: number;
  peakWeight: number;
  firstWeight: number;
  lastWeight: number;
  entries: ProgressEntry[];
};

export type ProgressDataBundle = {
  exerciseProgressData: ExerciseProgress[];
  programColors: Record<string, string>;
};

export function parseDateMs(s: string): number {
  const t = Date.parse(s);
  return Number.isNaN(t) ? 0 : t;
}

export function sortEntriesByDate(entries: ProgressEntry[]): ProgressEntry[] {
  return [...entries].sort((a, b) => parseDateMs(a.date) - parseDateMs(b.date));
}

export function recomputeExercise(ex: ExerciseProgress): ExerciseProgress | null {
  const entries = sortEntriesByDate(ex.entries);
  if (entries.length === 0) return null;
  const weights = entries.map((e) => e.weight);
  return {
    ...ex,
    sessionCount: entries.length,
    peakWeight: Math.max(...weights),
    firstWeight: entries[0]!.weight,
    lastWeight: entries[entries.length - 1]!.weight,
    entries,
  };
}

/** Remove entries by index for one exercise; drops empty exercises; recomputes aggregates. */
export function removeEntriesFromExercise(
  bundle: ProgressDataBundle,
  exerciseIndex: number,
  entryIndicesToRemove: Set<number>
): ProgressDataBundle {
  const list = [...bundle.exerciseProgressData];
  const ex = list[exerciseIndex];
  if (!ex) {
    return bundle;
  }
  const nextEntries = ex.entries.filter((_, i) => !entryIndicesToRemove.has(i));
  const nextEx = recomputeExercise({ ...ex, entries: nextEntries });
  if (nextEx === null) {
    list.splice(exerciseIndex, 1);
  } else {
    list[exerciseIndex] = nextEx;
  }
  return {
    exerciseProgressData: list,
    programColors: { ...bundle.programColors },
  };
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

export function parseProgressBundle(raw: unknown): ProgressDataBundle {
  if (!isRecord(raw)) throw new Error("Payload must be a JSON object");
  const epRaw = raw.exerciseProgressData;
  if (!Array.isArray(epRaw)) throw new Error("exerciseProgressData must be an array");
  const exerciseProgressData: ExerciseProgress[] = [];
  for (const item of epRaw) {
    if (!isRecord(item)) throw new Error("Invalid exercise entry");
    const name = typeof item.name === "string" ? item.name : "";
    const entriesRaw = item.entries;
    if (!Array.isArray(entriesRaw)) throw new Error(`entries must be an array for “${name}”`);
    const entries: ProgressEntry[] = [];
    for (const er of entriesRaw) {
      if (!isRecord(er)) continue;
      const date = typeof er.date === "string" ? er.date : "";
      const weight = typeof er.weight === "number" && Number.isFinite(er.weight) ? er.weight : 0;
      const reps = typeof er.reps === "number" && Number.isFinite(er.reps) ? Math.round(er.reps) : 0;
      const maxReps =
        typeof er.maxReps === "number" && Number.isFinite(er.maxReps) ? Math.round(er.maxReps) : reps;
      const program = typeof er.program === "string" ? er.program : "";
      const dayTitle = typeof er.dayTitle === "string" ? er.dayTitle : "";
      let substitutedPerformedAs: string | null | undefined;
      if (er.substitutedPerformedAs === null || er.substitutedPerformedAs === undefined) {
        substitutedPerformedAs = er.substitutedPerformedAs ?? undefined;
      } else if (typeof er.substitutedPerformedAs === "string") {
        substitutedPerformedAs = er.substitutedPerformedAs;
      }
      entries.push({
        date,
        weight,
        reps,
        maxReps,
        program,
        dayTitle,
        substitutedPerformedAs: substitutedPerformedAs ?? null,
      });
    }
    const recomputed = recomputeExercise({
      name,
      sessionCount: typeof item.sessionCount === "number" ? item.sessionCount : entries.length,
      peakWeight: typeof item.peakWeight === "number" ? item.peakWeight : 0,
      firstWeight: typeof item.firstWeight === "number" ? item.firstWeight : 0,
      lastWeight: typeof item.lastWeight === "number" ? item.lastWeight : 0,
      entries,
    });
    if (recomputed) exerciseProgressData.push(recomputed);
  }
  let programColors: Record<string, string> = {};
  if (isRecord(raw.programColors)) {
    programColors = Object.fromEntries(
      Object.entries(raw.programColors).filter(
        ([k, v]) => typeof k === "string" && typeof v === "string"
      )
    ) as Record<string, string>;
  }
  return { exerciseProgressData, programColors };
}

export function downloadJson(data: unknown, filename: string): void {
  const blob = new Blob([JSON.stringify(data, null, 2)], {
    type: "application/json;charset=utf-8",
  });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
