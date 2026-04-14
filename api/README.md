# Blueprint API

**Express** (Node.js) server for **server-side OpenAI**, **workout catalog**, and **workout sync to Postgres**. The iOS app sends the user’s **Supabase access token** on protected routes (`Authorization: Bearer …`); the server verifies it with Supabase Auth. Public catalog reads use the server’s **anon** key against PostgREST so the app does not call `rest/v1` directly.

## Setup

```bash
cd api
cp .env.example .env
# Set OPENAI_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY (same anon key as the app).
# Optional: put secrets in .env.local (gitignored); it overrides .env when present.
npm install
npm run dev
```

`npm run dev` and `npm run start` load **`api/.env`** then **`api/.env.local`** (override). Run commands from the **`api`** directory so the files are found. Variable names are **`SUPABASE_ANON_KEY`** (uppercase) unless you use the supported alias **`supabase_anon_key`**.

Default port **8787**. The iOS `MergedConfig-Info.plist` sets `BLUEPRINT_API_URL` to `http://127.0.0.1:8787` for local dev.

## Endpoints

- `GET /health`
- `GET /v1/catalog/workout-programs` — public JSON matching the app's `WorkoutProgramsBundle` (programs + stats)
- `POST /v1/sync/workout` — JSON body: logged workout tree (`id`, ISO8601 `date`, optional program fields, `exercises[]` with `sets[]`). Requires a valid Supabase session bearer token; the server forwards writes to PostgREST as that user (same RLS as the old client).

- `POST /v1/ai/substitution-suggestions` — JSON: `{ prescribedExercise, userNote? }`
- `POST /v1/ai/import-program` — JSON: `{ text }` — paste-style import
- `POST /v1/ai/import-program/raw` — **body is the workout only**, UTF-8; use `Content-Type: text/plain` (or any non-JSON type). Same LLM step as above.
- `POST /v1/ai/import-program/upload` — `multipart/form-data` with field **`file`** (plain text, max 2MB)

**Import responses** (all three routes above) return JSON:

```json
{
  "program": { "name", "subtitle", "days": [ ... ] },
  "historicalWorkouts": [ ... ]
}
```

`historicalWorkouts` is an array of dated sessions with exercises and sets (for the app log) when the model finds parseable history; otherwise `[]`. The model is instructed to ignore noise (email footers, unrelated chat) and cap long histories (~200 sessions).
- `POST /v1/ai/related-exercises` — JSON: `{ exerciseName, allowedExactNames, limit? }`

All `/v1/ai/*` and `POST /v1/sync/workout` routes require a valid Supabase session bearer token.

### Example: import from a text file (curl)

```bash
export TOKEN="<supabase_access_jwt>"
curl -sS -X POST "http://127.0.0.1:8787/v1/ai/import-program/raw" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: text/plain; charset=utf-8" \
  --data-binary @./my-program.txt
```

Multipart:

```bash
curl -sS -X POST "http://127.0.0.1:8787/v1/ai/import-program/upload" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@./my-program.txt"
```

## Production

Set `BLUEPRINT_API_URL` to your deployed API (and keep `additional_redirect_urls` / auth aligned for the app). Use secrets management for `OPENAI_API_KEY` and never ship it in the client.
