#!/usr/bin/env npx tsx
/**
 * Copy all Blueprint Workout data from Supabase Postgres → Railway Postgres.
 *
 * Usage (from repo root or api/):
 *   SUPABASE_DB_PASSWORD='...' DATABASE_URL='...' npm run migrate:from-supabase --prefix api
 */
import pg from "pg";

const { Client } = pg;

function requireEnv(name: string): string {
  const v = process.env[name]?.trim();
  if (!v) throw new Error(`Missing ${name}`);
  return v;
}

/** Supabase session pooler (IPv4) when only the DB password is available. */
function supabaseDatabaseUrlCandidates(): string[] {
  const direct = process.env.SUPABASE_DATABASE_URL?.trim();
  if (direct) return [direct];

  const password = process.env.SUPABASE_DB_PASSWORD?.trim();
  if (!password) {
    throw new Error(
      "Set SUPABASE_DATABASE_URL or SUPABASE_DB_PASSWORD (Supabase Dashboard → Database → password)"
    );
  }

  const ref = process.env.SUPABASE_PROJECT_REF?.trim() || "wnynfibttseeagardfwb";
  const region = process.env.SUPABASE_DB_REGION?.trim() || "us-east-2";
  const port = process.env.SUPABASE_DB_PORT?.trim() || "5432";
  const encoded = encodeURIComponent(password);
  const userHost = `postgres.${ref}:${encoded}@`;

  const explicitHost = process.env.SUPABASE_POOLER_HOST?.trim();
  if (explicitHost) {
    return [`postgresql://${userHost}${explicitHost}:${port}/postgres`];
  }

  // Ohio and some other regions use aws-1, not aws-0 — try both unless host is set explicitly.
  const azPrefixes = process.env.SUPABASE_POOLER_AZ?.trim()
    ? [process.env.SUPABASE_POOLER_AZ.trim()]
    : ["1", "0"];
  return azPrefixes.map(
    (az) =>
      `postgresql://${userHost}aws-${az}-${region}.pooler.supabase.com:${port}/postgres`
  );
}

async function connectSupabase(): Promise<pg.Client> {
  const candidates = supabaseDatabaseUrlCandidates();
  let lastError: unknown;
  for (const url of candidates) {
    const client = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
    try {
      await client.connect();
      if (candidates.length > 1) {
        const host = new URL(url.replace(/^postgresql:/, "https:")).hostname;
        console.log(`Connected to Supabase via ${host}`);
      }
      return client;
    } catch (e) {
      lastError = e;
      await client.end().catch(() => undefined);
    }
  }
  throw lastError;
}

type TableSpec = {
  name: string;
  columns: string[];
  source?: string;
  sourceColumns?: string[];
  where?: string;
};

const TABLES: TableSpec[] = [
  {
    name: "users",
    columns: ["id", "email", "password_hash", "created_at", "updated_at"],
    source: "auth.users",
    sourceColumns: ["id", "email", "encrypted_password", "created_at", "updated_at"],
    where: "encrypted_password IS NOT NULL",
  },
  {
    name: "profiles",
    columns: ["id", "email", "display_name", "settings", "hub_state", "created_at", "updated_at"],
  },
  { name: "exercises", columns: ["id", "name", "name_key", "created_at"] },
  {
    name: "catalog_categories",
    columns: ["slug", "title", "subtitle", "sort_order", "icon_sf_symbol"],
  },
  {
    name: "catalog_programs",
    columns: [
      "id", "name", "subtitle", "period", "date_range", "color", "is_user_created",
      "created_by", "category_slug", "listing_status", "updated_at",
    ],
  },
  {
    name: "catalog_program_days",
    columns: ["id", "program_id", "day_index", "label"],
  },
  {
    name: "catalog_day_exercises",
    columns: [
      "id", "program_day_id", "exercise_id", "sort_order", "max_weight",
      "target_sets", "superset_group", "is_amrap", "is_warmup", "notes",
    ],
  },
  { name: "catalog_release", columns: ["id", "version", "notes", "published_at"] },
  { name: "bundled_progress_reference", columns: ["id", "payload", "updated_at"] },
  {
    name: "workouts",
    columns: [
      "id", "user_id", "client_workout_id", "logged_at", "program_id",
      "program_name", "day_label", "notes", "created_at", "updated_at",
    ],
  },
  {
    name: "workout_exercises",
    columns: [
      "id", "workout_id", "client_exercise_id", "name", "prescribed_name",
      "canonical_exercise_id", "sort_order",
    ],
  },
  {
    name: "workout_sets",
    columns: ["id", "exercise_id", "client_set_id", "weight", "reps", "sort_order"],
  },
  {
    name: "saved_programs",
    columns: ["id", "user_id", "program_id", "payload", "is_bundled_override", "created_at", "updated_at"],
  },
  {
    name: "program_library_entries",
    columns: ["user_id", "program_id", "created_at"],
  },
  {
    name: "user_progress_bundles",
    columns: ["user_id", "payload", "imported_at", "updated_at"],
  },
];

async function countRows(client: pg.Client, table: string): Promise<number> {
  const r = await client.query<{ c: string }>(`SELECT count(*)::text AS c FROM ${table}`);
  return parseInt(r.rows[0]?.c ?? "0", 10);
}

async function copyTable(src: pg.Client, dst: pg.Client, spec: TableSpec): Promise<number> {
  const sourceTable = spec.source ?? spec.name;
  const sourceCols = spec.sourceColumns ?? spec.columns;
  const colList = spec.columns.map((c) => `"${c}"`).join(", ");
  const selectList = sourceCols.map((c) => `"${c}"`).join(", ");
  const where = spec.where ? ` WHERE ${spec.where}` : "";

  const existing = await countRows(dst, spec.name);
  if (existing > 0) {
    console.log(`  skip ${spec.name} (${existing} rows already present)`);
    return existing;
  }

  const { rows } = await src.query(`SELECT ${selectList} FROM ${sourceTable}${where}`);
  if (rows.length === 0) {
    console.log(`  ${spec.name}: 0 rows`);
    return 0;
  }

  const batchSize = 200;
  let inserted = 0;
  for (let i = 0; i < rows.length; i += batchSize) {
    const batch = rows.slice(i, i + batchSize);
    const values: unknown[] = [];
    const tuples: string[] = [];
    batch.forEach((row, rowIdx) => {
      const placeholders = spec.columns.map((_, colIdx) => {
        values.push(row[sourceCols[colIdx]!]);
        return `$${rowIdx * spec.columns.length + colIdx + 1}`;
      });
      tuples.push(`(${placeholders.join(", ")})`);
    });
    await dst.query(
      `INSERT INTO ${spec.name} (${colList}) VALUES ${tuples.join(", ")} ON CONFLICT DO NOTHING`,
      values
    );
    inserted += batch.length;
  }
  console.log(`  ${spec.name}: ${inserted} rows`);
  return inserted;
}

async function main(): Promise<void> {
  const railwayUrl = requireEnv("DATABASE_URL");
  const dst = new Client({ connectionString: railwayUrl, ssl: { rejectUnauthorized: false } });

  console.log("Connecting…");
  const src = await connectSupabase();
  await dst.connect();

  console.log("Copying tables (source → Railway)…");
  for (const spec of TABLES) {
    await copyTable(src, dst, spec);
  }

  const userCount = await countRows(dst, "users");
  console.log(`\nDone. ${userCount} user(s) migrated.`);

  await src.end();
  await dst.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
