-- Shared reference curves from app bundle `progress_data.json` (same for all installs pre-cloud).
-- Distinct from `user_progress_bundles` (per-account imports).

create table public.bundled_progress_reference (
  id smallint primary key default 1 constraint bundled_progress_ref_singleton check (id = 1),
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

comment on table public.bundled_progress_reference is 'Singleton: ProgressDataBundle JSON shipped with the app; seeded for local/remote parity.';

alter table public.bundled_progress_reference enable row level security;

create policy "bundled_progress_reference_read"
  on public.bundled_progress_reference for select
  to authenticated, anon
  using (true);
