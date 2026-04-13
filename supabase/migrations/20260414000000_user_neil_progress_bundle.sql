-- Attach bundled reference progress to Neil’s account (same JSON as `bundled_progress_reference` / `progress_data.json`).
-- Safe to re-run: upserts by primary key.
--
-- Prerequisite: an Auth user with email neil@blueprintapps.io (sign up once). If the user does not exist yet,
-- this migration inserts zero rows; run again after signup or apply the same INSERT manually in SQL Editor.

insert into public.user_progress_bundles (user_id, payload)
select u.id, b.payload
from auth.users u
cross join public.bundled_progress_reference b
where lower(u.email) = lower('neil@blueprintapps.io')
  and b.id = 1
on conflict (user_id) do update
set
  payload = excluded.payload,
  updated_at = now();
