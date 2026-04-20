# Blueprint API

**Express** (Node.js) server for **server-side OpenAI**, **workout catalog**, and **workout sync to Postgres**. The iOS app sends the user’s **Supabase access token** on protected routes (`Authorization: Bearer …`); the server verifies it with Supabase Auth. Public catalog reads use the server’s **anon** key against PostgREST so the app does not call `rest/v1` directly.

Versioned resources live under **`/v1`**. **`GET /v1`** returns a small JSON map of available routes.

## Project layout (`api/src`)

| Path | Role |
|------|------|
| `index.ts` | Process entry: load env, `createApp()`, listen |
| `app.ts` | Express app: CORS, JSON body, `/health`, `/v1`, global error handler |
| `lib/` | Shared primitives (`http-error`) |
| `middleware/` | `auth`, `platform-admin`, `error-handler`, `program-import-body` (multer + text fallback) |
| `integrations/` | Supabase Auth + PostgREST clients |
| `services/` | Domain logic: `workout-catalog`, `workout-sync`, `catalog-publish`, `admin-seed-and-workouts`, `platform-admin`, `openai` (LLM + program import) |
| `routes/v1/` | HTTP adapters: `meta`, `*.routes.ts`, `index.ts` mounts sub-routers |

## Setup

```bash
cd api
cp .env.example .env
# Set OPENAI_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY (same anon key as the app).
# For `/v1/admin/*` (except where noted): SUPABASE_SERVICE_ROLE_KEY plus ADMIN_EMAILS and/or CATALOG_ADMIN_EMAILS (comma-separated).
# Optional: put secrets in .env.local (gitignored); it overrides .env when present.
npm install
npm run dev
```

`npm run dev` and `npm run start` load **`api/.env`** then **`api/.env.local`** (override). Run commands from the **`api`** directory so the files are found. Variable names are **`SUPABASE_ANON_KEY`** (uppercase) unless you use the supported alias **`supabase_anon_key`**.

Default port **8787**. The iOS `MergedConfig-Info.plist` sets `BLUEPRINT_API_URL` to `http://127.0.0.1:8787` for local dev.

## Endpoints

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | `/health` | — | Liveness |
| `GET` | `/v1` | — | API metadata and route map |
| `GET` | `/v1/catalog/programs` | — | Public JSON: `WorkoutProgramsBundle` (programs + stats) |
| `POST` | `/v1/workouts` | Bearer | Upsert logged workout (`id`, ISO8601 `date`, optional program fields, `exercises[]` / `sets[]`). **204** on success. |
| `POST` | `/v1/exercises/substitution-suggestions` | Bearer | JSON: `{ prescribedExercise, userNote? }` → `{ suggestions: string[] }` |
| `POST` | `/v1/exercises/related` | Bearer | JSON: `{ exerciseName, allowedExactNames, limit? }` → `{ related: string[] }` |
| `POST` | `/v1/imports/programs` | Bearer | AI program import (one of three bodies below) |
| `POST` | `/v1/admin/catalog/programs` | Bearer | Admin: publish/replace one catalog program graph (`services/catalog-publish.ts`) |
| `DELETE` | `/v1/admin/catalog/programs/:programId` | Bearer | Admin: remove catalog program (cascades days/lines); bumps `catalog_release` |
| `GET` | `/v1/admin/catalog/snapshot` | Bearer | Admin: `catalog_release`, exercise count, program id/name list |
| `GET` | `/v1/admin/exercises` | Bearer | Admin: search `public.exercises` (`q`, `limit`) |
| `GET` | `/v1/admin/bundled-progress` | Bearer | Admin: singleton `bundled_progress_reference` row |
| `PATCH` | `/v1/admin/bundled-progress` | Bearer | Admin: `{ "payload": { ... } }` JSON |
| `GET` | `/v1/admin/workouts` | Bearer | Admin: paginated workouts (`limit`, `offset`, `userId`, `email`, `programId`, `anomaly=1`, `unlinked=1`) |
| `GET` | `/v1/admin/workouts/:id` | Bearer | Admin: workout + exercises + sets + profile |
| `PATCH` | `/v1/admin/workouts/:id` | Bearer | Admin: `{ notes?, program_name?, day_label? }` |
| `DELETE` | `/v1/admin/workouts/:id` | Bearer | Admin: hard-delete workout (cascades) |
| `PATCH` | `/v1/admin/workout-exercises/:id` | Bearer | Admin: `{ canonical_exercise_id?, name?, prescribed_name? }` |
| `POST` | `/v1/admin/workout-exercises/bulk-link` | Bearer | Admin: `{ nameKey, canonicalExerciseId, dryRun? }` — link unlinked rows where `lower(trim(name))` equals normalized `nameKey` |

### Platform admin: anomaly rules

SQL view **`public.admin_workouts_with_anomalies`** (see migration `20260416180000_workout_exercises_canonical_and_anomaly_view.sql`) lists **`workout_id`** values where **any** exercise line on that workout has:

- **Blank name** (`trim(name) = ''`)
- **No sets** (no `workout_sets` rows for that line)
- **Implausible sets**: `reps <= 0`, `reps > 500`, `weight < 0`, or `weight > 3000`

`GET /v1/admin/workouts?anomaly=1` returns only workouts whose id appears in that view. **`unlinked=1`** restricts to workouts that have at least one `workout_exercises` row with **`canonical_exercise_id` is null** (capped server-side to **250** distinct workouts for the `in (...)` filter — narrow with `email` / `userId` if you hit the limit).

Allowlist env vars: **`ADMIN_EMAILS`** (comma-separated) and/or existing **`CATALOG_ADMIN_EMAILS`** / `CATALOG_ADMIN_EMAIL` / `ADMIN_EMAIL` — merged in [`platform-admin.ts`](src/services/platform-admin.ts).

### `POST /v1/imports/programs`

Same path; choose representation:

1. **JSON:** `Content-Type: application/json`, body `{ "text": "…" }` (paste-style).
2. **Plain text:** `Content-Type: text/plain; charset=utf-8` — body is the workout text only.
3. **Multipart:** `multipart/form-data`, field **`file`** (plain text, max 2MB).

**Response** (all three):

```json
{
  "program": { "name", "subtitle", "days": [ ... ] },
  "historicalWorkouts": [ ... ]
}
```

`historicalWorkouts` is dated sessions when the model finds parseable history; otherwise `[]`.

Protected routes (`/v1/workouts`, `/v1/exercises/*`, `/v1/imports/*`, `/v1/admin/*`) require a valid Supabase session bearer token.

### Example: import from a text file (curl)

```bash
export TOKEN="<supabase_access_jwt>"
curl -sS -X POST "http://127.0.0.1:8787/v1/imports/programs" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: text/plain; charset=utf-8" \
  --data-binary @./my-program.txt
```

Multipart:

```bash
curl -sS -X POST "http://127.0.0.1:8787/v1/imports/programs" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@./my-program.txt"
```

## Production

Set `BLUEPRINT_API_URL` to your deployed API (and keep `additional_redirect_urls` / auth aligned for the app). Use secrets management for `OPENAI_API_KEY` and never ship it in the client.
