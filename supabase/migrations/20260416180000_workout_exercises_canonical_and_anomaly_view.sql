-- Link logged exercises to catalog exercises + admin anomaly discovery (read via PostgREST / service role).

alter table public.workout_exercises
  add column if not exists canonical_exercise_id uuid references public.exercises (id) on delete set null;

comment on column public.workout_exercises.canonical_exercise_id is
  'Optional FK to public.exercises for analytics and deduping noisy free-text names; set by admin tooling.';

create index if not exists workout_exercises_canonical_exercise_id_idx
  on public.workout_exercises (canonical_exercise_id);

create index if not exists workout_exercises_unlinked_canonical_idx
  on public.workout_exercises (workout_id)
  where canonical_exercise_id is null;

-- Workouts that have at least one exercise line or set failing basic sanity checks.
create or replace view public.admin_workouts_with_anomalies with (security_invoker = true) as
select distinct w.id as workout_id
from public.workouts w
join public.workout_exercises we on we.workout_id = w.id
where trim(we.name) = ''
   or not exists (select 1 from public.workout_sets ws0 where ws0.exercise_id = we.id)
   or exists (
       select 1 from public.workout_sets ws1
       where ws1.exercise_id = we.id
         and (
           ws1.reps <= 0
           or ws1.reps > 500
           or ws1.weight < 0
           or ws1.weight > 3000
         )
     );

comment on view public.admin_workouts_with_anomalies is
  'Workout ids with data-quality issues (blank names, missing sets, implausible reps/weight). See api/README admin section.';
