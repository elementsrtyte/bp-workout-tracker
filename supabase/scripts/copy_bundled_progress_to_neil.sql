-- One-off: copy singleton bundled progress into neil@blueprintapps.io’s row.
-- Use when the Auth user was created *after* migration20260414000000 ran (that migration inserts zero rows if the user did not exist yet).
--
--   supabase db query --local  -f supabase/scripts/copy_bundled_progress_to_neil.sql
--   supabase db query --linked -f supabase/scripts/copy_bundled_progress_to_neil.sql

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
