-- Track who published a catalog program (null = official Blueprint seed / admin).

alter table public.catalog_programs
  add column if not exists created_by uuid references auth.users (id) on delete set null;

comment on column public.catalog_programs.created_by is 'Auth user who shared this program publicly; null for official catalog entries.';

create index if not exists catalog_programs_created_by_idx
  on public.catalog_programs (created_by)
  where created_by is not null;
