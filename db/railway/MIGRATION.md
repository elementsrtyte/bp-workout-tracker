# Railway Postgres migration (Supabase → workout project)

This guide moves Blueprint Workout off Supabase to **Railway Postgres** in the **`workout`** project, with auth handled by the Blueprint API.

## What changed in code

| Before | After |
|--------|--------|
| Supabase Postgres + PostgREST | Railway Postgres + direct SQL in API |
| Supabase GoTrue (`/auth/v1`) | Blueprint API (`/v1/auth/*`) |
| `SUPABASE_*` env vars on API | `DATABASE_URL` + `JWT_SECRET` |

User UUIDs and password hashes are **preserved** during migration so existing accounts keep working.

---

## Step 1 — Railway: add Postgres

```bash
railway login          # re-auth if MCP/CLI says Unauthorized
cd /path/to/bp-workout
railway link -p workout
railway add -d postgres
```

Note the **`DATABASE_URL`** from the Postgres service (Variables tab).

## Step 2 — Apply schema on Railway

```bash
railway run -s Postgres psql $DATABASE_URL -f db/railway/schema.sql
```

Or locally:

```bash
psql "$DATABASE_URL" -f db/railway/schema.sql
```

## Step 3 — Copy data from Supabase

Get the **Session pooler** connection string from Supabase Dashboard → Connect (port 5432). Copy the hostname exactly — Ohio projects often use `aws-1-us-east-2`, not `aws-0`.

```bash
cd api && npm install
# Option A — full URL from dashboard (recommended)
SUPABASE_DATABASE_URL="postgresql://postgres.[ref]:[password]@aws-1-us-east-2.pooler.supabase.com:5432/postgres" \
DATABASE_URL="postgresql://..." \
npm run migrate:from-supabase

# Option B — password only (script tries aws-1 then aws-0 for us-east-2)
SUPABASE_DB_PASSWORD='...' \
DATABASE_URL="postgresql://..." \
npm run migrate:from-supabase
```

Optional overrides: `SUPABASE_POOLER_HOST`, `SUPABASE_POOLER_AZ` (0 or 1), `SUPABASE_DB_REGION`, `SUPABASE_PROJECT_REF`.

The script copies:

- `auth.users` → `users` (password hashes preserved)
- All `public.*` tables in FK order

Refresh tokens are **not** migrated; users sign in again once the app points at the new API auth.

If catalog tables are empty after migration, apply seed migrations:

```bash
psql "$DATABASE_URL" -f supabase/migrations/20260412210000_seed_bundled_catalog_and_progress.sql
psql "$DATABASE_URL" -f supabase/migrations/20260415120000_program_marketplace_categories.sql
```

## Step 4 — Deploy API on Railway

Add a **service** for the API (GitHub repo or `railway up` from `api/`).

**Required variables** on the API service:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | Reference from Postgres service (`${{Postgres.DATABASE_URL}}`) |
| `JWT_SECRET` | Random string, **≥ 32 chars** (e.g. `openssl rand -base64 48`) |
| `OPENAI_API_KEY` | Existing OpenAI key |
| `ADMIN_EMAILS` | Comma-separated admin emails |
| `PORT` | `8787` (or Railway's injected `PORT`) |

Remove `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` from the API service.

## Step 5 — Update clients

### iOS (`MergedConfig-Info.plist`)

- Keep **`BLUEPRINT_API_URL`** pointing at your Railway API (e.g. `https://your-api.up.railway.app`)
- Remove **`SUPABASE_URL`** and **`SUPABASE_ANON_KEY`** (auth now uses the Blueprint API)

Users must **sign out and sign in** once after the app update (refresh tokens reset).

### Admin web (`.env`)

```
VITE_BLUEPRINT_API_URL=https://your-api.up.railway.app
```

Remove `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.

## Step 6 — Verify

```bash
# Health
curl https://your-api.up.railway.app/v1/

# Sign in (migrated user)
curl -X POST https://your-api.up.railway.app/v1/auth/token \
  -H 'Content-Type: application/json' \
  -d '{"grant_type":"password","email":"you@example.com","password":"..."}'

# Catalog
curl https://your-api.up.railway.app/v1/catalog/programs
```

## Step 7 — Decommission Supabase

After a soak period:

1. Confirm no traffic to Supabase (Dashboard → Logs)
2. Export a final backup if desired
3. Pause or delete the Supabase project

---

## Local development

```bash
# api/.env.local
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:5432/bp_workout
JWT_SECRET=local-dev-secret-at-least-32-characters-long
OPENAI_API_KEY=sk-...
ADMIN_EMAILS=you@example.com
PORT=8787
```

Run Postgres locally (Docker):

```bash
docker run --name bp-workout-pg -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=bp_workout -p 5432:5432 -d postgres:17
psql postgresql://postgres:postgres@127.0.0.1:5432/bp_workout -f db/railway/schema.sql
```

Then `cd api && npm run dev`.
