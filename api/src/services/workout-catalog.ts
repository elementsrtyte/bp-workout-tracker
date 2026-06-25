import { query } from "../db/pool.js";
import { HttpError } from "../lib/http-error.js";

type CatalogCategoryRow = {
  slug: string;
  title: string;
  subtitle: string;
  sort_order: number;
  icon_sf_symbol: string;
};

type CatalogProgramRow = {
  id: string;
  name: string;
  subtitle: string;
  period: string;
  date_range: string;
  color: string;
  is_user_created: boolean;
  category_slug: string | null;
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

type ExerciseRow = { id: string; name: string };

type Exercise = {
  name: string;
  maxWeight: string;
  targetSets: number | null;
  supersetGroup: number | null;
  isAmrap: boolean | null;
  isWarmup: boolean | null;
  notes: string | null;
};

type WorkoutDay = { label: string; exercises: Exercise[] };

type WorkoutProgram = {
  id: string;
  name: string;
  subtitle: string;
  period: string;
  dateRange: string;
  days: WorkoutDay[];
  color: string;
  isUserCreated: boolean | null;
  categorySlug: string | null;
  categoryTitle: string | null;
};

type CatalogCategory = {
  slug: string;
  title: string;
  subtitle: string;
  sortOrder: number;
  iconSfSymbol: string;
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
  categories: CatalogCategory[];
};

/** Public catalog from Railway Postgres. */
export async function fetchWorkoutProgramsBundle(): Promise<WorkoutProgramsBundle> {
  const [categoryRes, programsRes, daysRes, linesRes, exercisesRes] = await Promise.all([
    query<CatalogCategoryRow>(`SELECT slug, title, subtitle, sort_order, icon_sf_symbol FROM catalog_categories ORDER BY sort_order ASC`),
    query<CatalogProgramRow>(
      `SELECT id, name, subtitle, period, date_range, color, is_user_created, category_slug
       FROM catalog_programs WHERE listing_status = 'live' ORDER BY id ASC`
    ),
    query<CatalogProgramDayRow>(
      `SELECT id, program_id, day_index, label FROM catalog_program_days ORDER BY program_id ASC, day_index ASC`
    ),
    query<CatalogDayExerciseRow>(
      `SELECT program_day_id, sort_order, max_weight, target_sets, superset_group, is_amrap, is_warmup, notes, exercise_id
       FROM catalog_day_exercises ORDER BY program_day_id ASC, sort_order ASC`
    ),
    query<ExerciseRow>(`SELECT id, name FROM exercises`),
  ]);

  const categoryRows = categoryRes.rows;
  const programs = programsRes.rows;
  const days = daysRes.rows;
  const lines = linesRes.rows;
  const exercises = exercisesRes.rows;

  const categories: CatalogCategory[] = categoryRows.map((c) => ({
    slug: c.slug,
    title: c.title,
    subtitle: c.subtitle,
    sortOrder: c.sort_order,
    iconSfSymbol: c.icon_sf_symbol,
  }));
  const categoryTitleBySlug = new Map(categories.map((c) => [c.slug, c.title] as const));

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
    const slug = p.category_slug?.trim() || null;
    const catTitle = slug ? categoryTitleBySlug.get(slug) ?? null : null;
    workoutPrograms.push({
      id: p.id,
      name: p.name,
      subtitle: p.subtitle,
      period: p.period,
      dateRange: p.date_range,
      days: workoutDays,
      color: p.color,
      isUserCreated: p.is_user_created ? true : null,
      categorySlug: slug,
      categoryTitle: catTitle,
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
    categories,
  };
}
