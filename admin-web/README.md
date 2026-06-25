# Blueprint admin (web)

Small **Vite + React** SPA for platform admins: catalog snapshot, bundled progress JSON, and cross-user workout inspection / canonical exercise linking.

## Requirements

- Running **Blueprint API** with `DATABASE_URL`, `JWT_SECRET`, and **`ADMIN_EMAILS`** and/or **`CATALOG_ADMIN_EMAILS`** including your admin account email.

## Setup

```bash
cd admin-web
cp .env.example .env.local
# Set VITE_BLUEPRINT_API_URL in .env.local
npm install
npm run dev
```

Open the printed local URL (e.g. http://localhost:5173). Sign in with email/password. Non-allowlisted users get **403** from the API.

## Build

```bash
npm run build
npm run preview
```

Deploy the `dist/` folder to any static host; set `VITE_BLUEPRINT_API_URL` at build time.

## Related

- API admin routes: [api/README.md](../api/README.md) (Platform admin section).
- Schema reference: [db/railway/schema.sql](../db/railway/schema.sql).
