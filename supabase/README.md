# Supabase backend (Blueprint Workout)

Schema and auth config managed with the **Supabase CLI** only (`migrations/`, `config.toml`, `seed.sql`). No separate Node/npm toolchain in this repo.

**Catalog:** Tables `catalog_*` + `exercises` hold the normalized program graph (import strategy is up to you: SQL migrations, `db query`, or app-driven upserts). Clients should **cache** by `catalog_release.version` for snappy autocomplete.

**Progress bundle:** Table `user_progress_bundles` stores optional per-user `ProgressDataBundle` JSON (`payload`). Seed after the auth user exists.

## CLI workflow

```bash
# Local (Docker). If port 54322 is in use, stop other stacks or change [db].port in config.toml.
supabase start
supabase db reset          # migrations + seed.sql

# New change
supabase migration new describe_change
# edit supabase/migrations/<timestamp>_describe_change.sql
supabase db reset          # re-apply locally

# Hosted
supabase login
supabase link --project-ref <ref>
supabase db push
```

**Run ad-hoc SQL** (local default, or target linked project):

```bash
supabase db query --local -f ./path/to/script.sql
supabase db query --linked -f ./path/to/script.sql
# inline:
supabase db query --local "select * from catalog_release;"
```

Use **`--linked`** only after `supabase link`. For hosted DB URLs you can also pass `--db-url` (percent-encoded).

Other useful commands: `supabase status`, `supabase db diff`, `supabase db pull`.

After `supabase start`: Studio `http://127.0.0.1:54323`, Inbucket (auth emails) `http://127.0.0.1:54324`.

## Schema overview

| Table | Purpose |
|--------|---------|
| `profiles` | One row per `auth.users`; `settings`, `hub_state` JSON. |
| `workouts` / `workout_exercises` / `workout_sets` | Logged sessions (+ optional client UUIDs). |
| `saved_programs` | User programs / overrides (`payload` JSON). |
| `program_library_entries` | Program ids enabled in profile picker. |
| `exercises` | Canonical exercises (`name_key` unique). |
| `catalog_programs` / `catalog_program_days` / `catalog_day_exercises` | Normalized catalog. |
| `catalog_release` | Singleton `version` for cache invalidation. |
| `programs_including_exercise` | View for “programs that include exercise X”. |
| `user_progress_bundles` | Per-user `ProgressDataBundle` in `payload` (optional). |

App calls PostgREST with the user JWT; **anon** can read catalog tables per RLS. Service role is for admin automation only (never ship in the app).

## Loading catalog or `progress_data` (CLI-oriented)

- **Small / repeatable seeds:** add SQL to `seed.sql` or a dedicated migration.
- **Large JSON:** generate a `.sql` file locally (your own one-off tool) that `INSERT`s or `upsert`s rows, then run:

  `supabase db query --local -f ./generated.sql`  
  or `--linked` against production when ready.

- **`user_progress_bundles` for `neil@blueprintapps.io`:** create the user first (Auth). Then run SQL with their UUID, e.g.:

  ```sql
  insert into public.user_progress_bundles (user_id, payload)
  values (
    '<auth-user-uuid>'::uuid,
    '<valid ProgressDataBundle json>'::jsonb
  )
  on conflict (user_id) do update
    set payload = excluded.payload,
        imported_at = now(),
        updated_at = now();
  ```

  For very large JSON, keep the payload in a file and use `psql` `\copy` / `\i` with the DB connection string from `supabase status` (see Supabase docs for local Postgres URL), or split into a migration you generate once.

## Example query

```sql
select program_id, program_name
from programs_including_exercise
where name_key = 'leg press';
```

## On-device vs cloud

- **Device:** cache of catalog; bundled `workout_programs.json` / `progress_data.json` as bootstrap/offline.
- **Cloud:** `catalog_*`, `exercises`, `user_progress_bundles`, `workouts`, `saved_programs`, library + profile fields.

## Forgot password

Configure **Site URL** and **Redirect URLs** in the hosted dashboard to match `config.toml`. App uses Supabase Auth recovery + deep link; see [Native mobile deep linking (Swift)](https://supabase.com/docs/guides/auth/native-mobile-deep-linking?platform=swift).

## Files in this folder

- `migrations/` — versioned SQL.
- `config.toml` — local stack; mirror important auth URL settings in the dashboard for hosted.
- `seed.sql` — optional dev seed (runs on `db reset`).
