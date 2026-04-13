-- Session exercise substitutions: preserve prescribed vs performed names for history, PRs, and reinstall sync.

alter table public.workouts
  add column if not exists program_id text;

comment on column public.workouts.program_id is 'Stable WorkoutProgram.id when logged from the hub; null for ad-hoc sessions.';

alter table public.workout_exercises
  add column if not exists prescribed_name text;

comment on column public.workout_exercises.prescribed_name is 'Program template name for this line when the user substituted equipment; null if performed as prescribed. Column name remains the movement actually logged.';
