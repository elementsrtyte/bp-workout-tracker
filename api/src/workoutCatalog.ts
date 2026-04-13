import { HttpError } from "./httpError.js";
import { restJson, supabaseAnonKey } from "./supabaseData.js";

type CatalogProgramRow = {
  id: string;
  name: string;
  subtitle: string;
  period: string;
  date_range: string;
  color: string;
  is_user_created: boolean;
};

type CatalogProgramDayRow = {
  id: string;
  program_id: string;
  day_index: number;
  label: string;
};

type CatalogDayExerciseRow = {
  program_day_id: string;
  sort_order: number;
  max_weight: string;
  target_sets: number | null;
  superset_group: number | null;
  is_amrap: boolean | null;
  is_warmup: boolean | null;
  notes: string | null;
  exercise_id: string;
};

type ExerciseRow = {
  id: string;
  name: string;
};

type Exercise = {
  name: string;
  maxWeight: string;
  targetSets: number | null;
  supersetGroup: number | null;
  isAmrap: boolean | null;
  isWarmup: boolean | null;
  notes: string | null;
};

type WorkoutDay = {
  label: string;
  exercises: Exercise[];
};

type WorkoutProgram = {
  id: string;
  name: string;
  subtitle: string;
  period: string;
  dateRange: string;
  days: WorkoutDay[];
  color: string;
  isUserCreated: boolean | null;
};

type ProgramStats = {
  totalPrograms: number;
  totalMonths: number;
  totalWorkoutDays: number;
  dateRange: string;
};

export type WorkoutProgramsBundle = {
  programs: WorkoutProgram[];
  stats: ProgramStats;
};

/** Public catalog via PostgREST + anon JWT (same access the app used client-side). */
export async function fetchWorkoutProgramsBundle(): Promise<WorkoutProgramsBundle> {
  const anon = supabaseAnonKey();

  const [programs, days, lines, exercises] = await Promise.all([
    restJson<CatalogProgramRow[]>("catalog_programs", anon, ""),
    restJson<CatalogProgramDayRow[]>(
      "catalog_program_days",
      anon,
      "order=program_id.asc,day_index.asc"
    ),
    restJson<CatalogDayExerciseRow[]>(
      "catalog_day_exercises",
      anon,
      "order=program_day_id.asc,sort_order.asc"
    ),
    restJson<ExerciseRow[]>("exercises", anon, "select=id,name"),
  ]);

  const exById = new Map(exercises.map((e) => [e.id, e] as const));
  const linesByDay = new Map<string, CatalogDayExerciseRow[]>();
  for (const line of lines) {
    const arr = linesByDay.get(line.program_day_id) ?? [];
    arr.push(line);
    linesByDay.set(line.program_day_id, arr);
  }

  const daysByProgram = new Map<string, CatalogProgramDayRow[]>();
  for (const d of days) {
    const arr = daysByProgram.get(d.program_id) ?? [];
    arr.push(d);
    daysByProgram.set(d.program_id, arr);
  }
  for (const arr of daysByProgram.values()) {
    arr.sort((a, b) => a.day_index - b.day_index);
  }

  const workoutPrograms: WorkoutProgram[] = [];
  for (const p of [...programs].sort((a, b) => a.id.localeCompare(b.id))) {
    const dayRows = daysByProgram.get(p.id) ?? [];
    const workoutDays: WorkoutDay[] = [];
    for (const d of dayRows) {
      const lineRows = (linesByDay.get(d.id) ?? []).sort((a, b) => a.sort_order - b.sort_order);
      const exs: Exercise[] = [];
      for (const line of lineRows) {
        const exRow = exById.get(line.exercise_id);
        if (!exRow) {
          throw new HttpError(502, `Missing exercise ${line.exercise_id} for program ${p.id}`);
        }
        exs.push({
          name: exRow.name,
          maxWeight: line.max_weight,
          targetSets: line.target_sets,
          supersetGroup: line.superset_group,
          isAmrap: line.is_amrap,
          isWarmup: line.is_warmup,
          notes: line.notes,
        });
      }
      workoutDays.push({ label: d.label, exercises: exs });
    }
    workoutPrograms.push({
      id: p.id,
      name: p.name,
      subtitle: p.subtitle,
      period: p.period,
      dateRange: p.date_range,
      days: workoutDays,
      color: p.color,
      isUserCreated: p.is_user_created ? true : null,
    });
  }

  const totalDays = workoutPrograms.reduce((acc, pr) => acc + pr.days.length, 0);
  return {
    programs: workoutPrograms,
    stats: {
      totalPrograms: workoutPrograms.length,
      totalMonths: 0,
      totalWorkoutDays: totalDays,
      dateRange: "",
    },
  };
}
