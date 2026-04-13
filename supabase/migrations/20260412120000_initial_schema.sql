-- Blueprint Workout — initial schema
-- Auth: Supabase Auth (email/password). RLS on all user tables.

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  -- Mirrors AppSettings + WorkoutHub convenience (sync optional fields as you wire the client)
  settings jsonb not null default '{}'::jsonb,
  -- e.g. { "active_program_id": "...", "day_index_by_program": { "pid": 0 }, "draft": { ... } }
  hub_state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'App profile; created on signup via trigger.';
comment on column public.profiles.settings is 'Client preferences: filter_anomalies, anomaly_sensitivity, min_reps, program_admin_mode, etc.';
comment on column public.profiles.hub_state is 'Ephemeral UX state: active program, per-program day index, in-progress draft JSON.';

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Logged workouts (replaces SwiftData LoggedWorkout tree)
-- ---------------------------------------------------------------------------
create table public.workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Stable id from the iOS client for idempotent upserts during migration / offline sync
  client_workout_id uuid,
  logged_at timestamptz not null,
  program_name text,
  day_label text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index workouts_user_client_id_key
  on public.workouts (user_id, client_workout_id)
  where client_workout_id is not null;

create index workouts_user_logged_at_idx on public.workouts (user_id, logged_at desc);

create trigger workouts_set_updated_at
  before update on public.workouts
  for each row
  execute function public.set_updated_at();

create table public.workout_exercises (
  id uuid primary key default gen_random_uuid(),
  workout_id uuid not null references public.workouts (id) on delete cascade,
  client_exercise_id uuid,
  name text not null,
  sort_order int not null default 0
);

create index workout_exercises_workout_id_idx on public.workout_exercises (workout_id);

create table public.workout_sets (
  id uuid primary key default gen_random_uuid(),
  exercise_id uuid not null references public.workout_exercises (id) on delete cascade,
  client_set_id uuid,
  weight double precision not null,
  reps int not null,
  sort_order int not null default 0
);

create index workout_sets_exercise_id_idx on public.workout_sets (exercise_id);

-- ---------------------------------------------------------------------------
-- User-defined / overridden programs (replaces Application Support user_programs.json)
-- ---------------------------------------------------------------------------
create table public.saved_programs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  -- Logical id from the app (WorkoutProgram.id); stable across devices
  program_id text not null,
  -- Full WorkoutProgram JSON as stored by the app today
  payload jsonb not null,
  is_bundled_override boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, program_id)
);

create trigger saved_programs_set_updated_at
  before update on public.saved_programs
  for each row
  execute function public.set_updated_at();

comment on table public.saved_programs is 'Custom programs and bundled overrides; bundle JSON stays in the app, only user edits here.';

-- ---------------------------------------------------------------------------
-- Programs visible in the user profile picker (replaces UserProgramLibrary)
-- ---------------------------------------------------------------------------
create table public.program_library_entries (
  user_id uuid not null references auth.users (id) on delete cascade,
  program_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, program_id)
);

-- ---------------------------------------------------------------------------
-- Auth: auto-create profile
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.workouts enable row level security;
alter table public.workout_exercises enable row level security;
alter table public.workout_sets enable row level security;
alter table public.saved_programs enable row level security;
alter table public.program_library_entries enable row level security;

-- Profiles: users can read/update own row (insert only via trigger)
create policy "profiles_select_own"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id);

-- Workouts tree
create policy "workouts_select_own"
  on public.workouts for select
  using (auth.uid() = user_id);

create policy "workouts_insert_own"
  on public.workouts for insert
  with check (auth.uid() = user_id);

create policy "workouts_update_own"
  on public.workouts for update
  using (auth.uid() = user_id);

create policy "workouts_delete_own"
  on public.workouts for delete
  using (auth.uid() = user_id);

create policy "workout_exercises_select_own"
  on public.workout_exercises for select
  using (
    exists (
      select 1 from public.workouts w
      where w.id = workout_exercises.workout_id and w.user_id = auth.uid()
    )
  );

create policy "workout_exercises_insert_own"
  on public.workout_exercises for insert
  with check (
    exists (
      select 1 from public.workouts w
      where w.id = workout_exercises.workout_id and w.user_id = auth.uid()
    )
  );

create policy "workout_exercises_update_own"
  on public.workout_exercises for update
  using (
    exists (
      select 1 from public.workouts w
      where w.id = workout_exercises.workout_id and w.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.workouts w
      where w.id = workout_exercises.workout_id and w.user_id = auth.uid()
    )
  );

create policy "workout_exercises_delete_own"
  on public.workout_exercises for delete
  using (
    exists (
      select 1 from public.workouts w
      where w.id = workout_exercises.workout_id and w.user_id = auth.uid()
    )
  );

create policy "workout_sets_select_own"
  on public.workout_sets for select
  using (
    exists (
      select 1 from public.workout_exercises e
      join public.workouts w on w.id = e.workout_id
      where e.id = workout_sets.exercise_id and w.user_id = auth.uid()
    )
  );

create policy "workout_sets_insert_own"
  on public.workout_sets for insert
  with check (
    exists (
      select 1 from public.workout_exercises e
      join public.workouts w on w.id = e.workout_id
      where e.id = workout_sets.exercise_id and w.user_id = auth.uid()
    )
  );

create policy "workout_sets_update_own"
  on public.workout_sets for update
  using (
    exists (
      select 1 from public.workout_exercises e
      join public.workouts w on w.id = e.workout_id
      where e.id = workout_sets.exercise_id and w.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.workout_exercises e
      join public.workouts w on w.id = e.workout_id
      where e.id = workout_sets.exercise_id and w.user_id = auth.uid()
    )
  );

create policy "workout_sets_delete_own"
  on public.workout_sets for delete
  using (
    exists (
      select 1 from public.workout_exercises e
      join public.workouts w on w.id = e.workout_id
      where e.id = workout_sets.exercise_id and w.user_id = auth.uid()
    )
  );

create policy "saved_programs_select_own"
  on public.saved_programs for select
  using (auth.uid() = user_id);

create policy "saved_programs_insert_own"
  on public.saved_programs for insert
  with check (auth.uid() = user_id);

create policy "saved_programs_update_own"
  on public.saved_programs for update
  using (auth.uid() = user_id);

create policy "saved_programs_delete_own"
  on public.saved_programs for delete
  using (auth.uid() = user_id);

create policy "program_library_select_own"
  on public.program_library_entries for select
  using (auth.uid() = user_id);

create policy "program_library_insert_own"
  on public.program_library_entries for insert
  with check (auth.uid() = user_id);

create policy "program_library_delete_own"
  on public.program_library_entries for delete
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Realtime (optional): replicate workouts for live UI
-- ---------------------------------------------------------------------------
alter publication supabase_realtime add table public.workouts;
