-- Blueprint catalog: normalized exercises + program graph for DB-backed catalog and search.
-- Client: fetch once (or when catalog_release.version changes), cache locally for autocomplete.

-- ---------------------------------------------------------------------------
-- Canonical exercises (deduped by display name → name_key)
-- ---------------------------------------------------------------------------
create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_key text not null,
  created_at timestamptz not null default now(),
  unique (name_key)
);

comment on table public.exercises is 'Shared exercise entities; programs reference these rows for search (programs containing exercise X).';
comment on column public.exercises.name_key is 'Normalized key: lower(trim(name)) — align with app ExerciseNameNormalizer.';

create index exercises_name_idx on public.exercises (name);

-- ---------------------------------------------------------------------------
-- Published Blueprint programs (bundle JSON synced from workout_programs.json)
-- User-authored programs stay in saved_programs; this table is the shared catalog only.
-- ---------------------------------------------------------------------------
create table public.catalog_programs (
  id text primary key,
  name text not null,
  subtitle text not null default '',
  period text not null default '',
  date_range text not null default '',
  color text not null default '#66bfcc',
  is_user_created boolean not null default false,
  updated_at timestamptz not null default now()
);

create trigger catalog_programs_set_updated_at
  before update on public.catalog_programs
  for each row
  execute function public.set_updated_at();

create table public.catalog_program_days (
  id uuid primary key default gen_random_uuid(),
  program_id text not null references public.catalog_programs (id) on delete cascade,
  day_index int not null,
  label text not null,
  unique (program_id, day_index)
);

create index catalog_program_days_program_id_idx on public.catalog_program_days (program_id);

create table public.catalog_day_exercises (
  id uuid primary key default gen_random_uuid(),
  program_day_id uuid not null references public.catalog_program_days (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete restrict,
  sort_order int not null default 0,
  max_weight text not null default '',
  target_sets int,
  superset_group int,
  is_amrap boolean,
  is_warmup boolean,
  notes text,
  unique (program_day_id, sort_order)
);

create index catalog_day_exercises_exercise_id_idx on public.catalog_day_exercises (exercise_id);
create index catalog_day_exercises_program_day_id_idx on public.catalog_day_exercises (program_day_id);

comment on table public.catalog_day_exercises is 'Prescription line: links a catalog day to a canonical exercise.';

-- ---------------------------------------------------------------------------
-- Cache-bust token for clients (bump when you re-import catalog)
-- ---------------------------------------------------------------------------
create table public.catalog_release (
  id smallint primary key default 1 constraint catalog_release_singleton check (id = 1),
  version int not null default 1,
  notes text,
  published_at timestamptz not null default now()
);

insert into public.catalog_release (id, version, notes)
values (1, 1, 'initial')
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Convenience view: program ↔ exercise (for “programs that include X”)
-- ---------------------------------------------------------------------------
create or replace view public.programs_including_exercise with (security_invoker = true) as
select
  e.id as exercise_id,
  e.name as exercise_name,
  e.name_key,
  cp.id as program_id,
  cp.name as program_name,
  cp.subtitle as program_subtitle
from public.catalog_day_exercises cde
join public.exercises e on e.id = cde.exercise_id
join public.catalog_program_days d on d.id = cde.program_day_id
join public.catalog_programs cp on cp.id = d.program_id;

comment on view public.programs_including_exercise is 'Filter by name_key or exercise_id to find catalog programs.';

-- ---------------------------------------------------------------------------
-- RLS: catalog is read-only for app users; writes via service role (import script).
-- ---------------------------------------------------------------------------
alter table public.exercises enable row level security;
alter table public.catalog_programs enable row level security;
alter table public.catalog_program_days enable row level security;
alter table public.catalog_day_exercises enable row level security;
alter table public.catalog_release enable row level security;

create policy "exercises_read_catalog"
  on public.exercises for select
  to authenticated, anon
  using (true);

create policy "catalog_programs_read"
  on public.catalog_programs for select
  to authenticated, anon
  using (true);

create policy "catalog_program_days_read"
  on public.catalog_program_days for select
  to authenticated, anon
  using (true);

create policy "catalog_day_exercises_read"
  on public.catalog_day_exercises for select
  to authenticated, anon
  using (true);

create policy "catalog_release_read"
  on public.catalog_release for select
  to authenticated, anon
  using (true);
