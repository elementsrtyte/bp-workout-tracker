# Blueprint admin (web)

Small **Vite + React** SPA for platform admins: catalog snapshot, bundled progress JSON, and cross-user workout inspection / canonical exercise linking.

## Requirements

- Supabase project (same as the app) — **anon** key in the browser only.
- Running **Blueprint API** with `SUPABASE_SERVICE_ROLE_KEY` and **`ADMIN_EMAILS`** and/or **`CATALOG_ADMIN_EMAILS`** including your Supabase account email.

## Setup

```bash
cd admin-web
cp .env.example .env.local
# Edit .env.local
npm install
npm run dev
```

Open the printed local URL (e.g. http://localhost:5173). Sign in with email/password. Non-allowlisted users get **403** from the API.

## Build

```bash
npm run build
npm run preview
```

Deploy the `dist/` folder to any static host; set the same `VITE_*` variables at build time.

## Related

- API admin routes: [api/README.md](../api/README.md) (Platform admin section).
- Migration for `canonical_exercise_id` and anomaly view: `supabase/migrations/20260416180000_workout_exercises_canonical_and_anomaly_view.sql`.
