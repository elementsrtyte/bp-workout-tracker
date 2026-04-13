-- Per-user progress bundle (historical / imported ProgressDataBundle JSON).
-- Most users: empty or populated from their logged workouts over time.
-- One-off imports (e.g. Neil’s bundled progress_data.json) run after the auth user exists.

create table public.user_progress_bundles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- Same shape as app ProgressDataBundle: { "exerciseProgressData": [...], "programColors": { ... } }
  payload jsonb not null,
  imported_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.user_progress_bundles is 'Optional reference progress curves; RLS limits access to the owning user.';

create trigger user_progress_bundles_set_updated_at
  before update on public.user_progress_bundles
  for each row
  execute function public.set_updated_at();

alter table public.user_progress_bundles enable row level security;

create policy "user_progress_bundles_select_own"
  on public.user_progress_bundles for select
  using (auth.uid() = user_id);

create policy "user_progress_bundles_insert_own"
  on public.user_progress_bundles for insert
  with check (auth.uid() = user_id);

create policy "user_progress_bundles_update_own"
  on public.user_progress_bundles for update
  using (auth.uid() = user_id);

create policy "user_progress_bundles_delete_own"
  on public.user_progress_bundles for delete
  using (auth.uid() = user_id);
