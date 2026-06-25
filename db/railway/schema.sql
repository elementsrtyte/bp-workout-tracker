-- Blueprint Workout — Railway Postgres schema
-- Replaces Supabase (auth.users + PostgREST + RLS). Auth enforced in the API layer.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Users (migrated from Supabase auth.users)
-- ---------------------------------------------------------------------------
CREATE TABLE users (
  id uuid PRIMARY KEY,
  email text UNIQUE,
  password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE refresh_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX refresh_tokens_user_id_idx ON refresh_tokens (user_id);
CREATE INDEX refresh_tokens_expires_at_idx ON refresh_tokens (expires_at);

-- ---------------------------------------------------------------------------
-- Profiles
-- ---------------------------------------------------------------------------
CREATE TABLE profiles (
  id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  email text,
  display_name text,
  settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  hub_state jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Catalog exercises (before workout_exercises FK)
-- ---------------------------------------------------------------------------
CREATE TABLE exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  name_key text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX exercises_name_idx ON exercises (name);

CREATE TABLE catalog_categories (
  slug text PRIMARY KEY,
  title text NOT NULL,
  subtitle text NOT NULL DEFAULT '',
  sort_order int NOT NULL DEFAULT 0,
  icon_sf_symbol text NOT NULL DEFAULT 'figure.strengthtraining.traditional'
);

INSERT INTO catalog_categories (slug, title, subtitle, sort_order, icon_sf_symbol) VALUES
  ('featured', 'Featured', 'Curated picks', 0, 'star.fill'),
  ('strength', 'Strength', 'Heavy compounds & progression', 10, 'dumbbell.fill'),
  ('hypertrophy', 'Hypertrophy', 'Volume & muscle building', 20, 'figure.strengthtraining.functional'),
  ('athletic', 'Athletic', 'Performance & conditioning', 30, 'figure.run'),
  ('beginner', 'Beginner', 'Simple full-body friendly', 40, 'leaf.fill'),
  ('specialty', 'Specialty', 'Arms, abs, and focused splits', 50, 'sparkles')
ON CONFLICT (slug) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Workouts
-- ---------------------------------------------------------------------------
CREATE TABLE workouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  client_workout_id uuid,
  logged_at timestamptz NOT NULL,
  program_id text,
  program_name text,
  day_label text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX workouts_user_client_id_key
  ON workouts (user_id, client_workout_id)
  WHERE client_workout_id IS NOT NULL;

CREATE INDEX workouts_user_logged_at_idx ON workouts (user_id, logged_at DESC);

CREATE TABLE workout_exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workout_id uuid NOT NULL REFERENCES workouts (id) ON DELETE CASCADE,
  client_exercise_id uuid,
  name text NOT NULL,
  prescribed_name text,
  canonical_exercise_id uuid REFERENCES exercises (id) ON DELETE SET NULL,
  sort_order int NOT NULL DEFAULT 0
);

CREATE INDEX workout_exercises_workout_id_idx ON workout_exercises (workout_id);
CREATE INDEX workout_exercises_canonical_exercise_id_idx ON workout_exercises (canonical_exercise_id);
CREATE INDEX workout_exercises_unlinked_canonical_idx ON workout_exercises (workout_id)
  WHERE canonical_exercise_id IS NULL;

CREATE TABLE workout_sets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  exercise_id uuid NOT NULL REFERENCES workout_exercises (id) ON DELETE CASCADE,
  client_set_id uuid,
  weight double precision NOT NULL,
  reps int NOT NULL,
  sort_order int NOT NULL DEFAULT 0
);

CREATE INDEX workout_sets_exercise_id_idx ON workout_sets (exercise_id);

-- ---------------------------------------------------------------------------
-- Saved programs & library
-- ---------------------------------------------------------------------------
CREATE TABLE saved_programs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  program_id text NOT NULL,
  payload jsonb NOT NULL,
  is_bundled_override boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, program_id)
);

CREATE TABLE program_library_entries (
  user_id uuid NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  program_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, program_id)
);

-- ---------------------------------------------------------------------------
-- Progress bundles
-- ---------------------------------------------------------------------------
CREATE TABLE user_progress_bundles (
  user_id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
  payload jsonb NOT NULL,
  imported_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE bundled_progress_reference (
  id smallint PRIMARY KEY DEFAULT 1 CONSTRAINT bundled_progress_ref_singleton CHECK (id = 1),
  payload jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Catalog programs
-- ---------------------------------------------------------------------------
CREATE TABLE catalog_programs (
  id text PRIMARY KEY,
  name text NOT NULL,
  subtitle text NOT NULL DEFAULT '',
  period text NOT NULL DEFAULT '',
  date_range text NOT NULL DEFAULT '',
  color text NOT NULL DEFAULT '#66bfcc',
  is_user_created boolean NOT NULL DEFAULT false,
  created_by uuid REFERENCES users (id) ON DELETE SET NULL,
  category_slug text NOT NULL DEFAULT 'strength' REFERENCES catalog_categories (slug) ON UPDATE CASCADE ON DELETE RESTRICT,
  listing_status text NOT NULL DEFAULT 'live' CHECK (listing_status IN ('live', 'draft', 'pending_review')),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX catalog_programs_created_by_idx ON catalog_programs (created_by) WHERE created_by IS NOT NULL;
CREATE INDEX catalog_programs_category_listing_idx ON catalog_programs (category_slug, listing_status);

CREATE TABLE catalog_program_days (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id text NOT NULL REFERENCES catalog_programs (id) ON DELETE CASCADE,
  day_index int NOT NULL,
  label text NOT NULL,
  UNIQUE (program_id, day_index)
);

CREATE INDEX catalog_program_days_program_id_idx ON catalog_program_days (program_id);

CREATE TABLE catalog_day_exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  program_day_id uuid NOT NULL REFERENCES catalog_program_days (id) ON DELETE CASCADE,
  exercise_id uuid NOT NULL REFERENCES exercises (id) ON DELETE RESTRICT,
  sort_order int NOT NULL DEFAULT 0,
  max_weight text NOT NULL DEFAULT '',
  target_sets int,
  superset_group int,
  is_amrap boolean,
  is_warmup boolean,
  notes text,
  UNIQUE (program_day_id, sort_order)
);

CREATE INDEX catalog_day_exercises_exercise_id_idx ON catalog_day_exercises (exercise_id);
CREATE INDEX catalog_day_exercises_program_day_id_idx ON catalog_day_exercises (program_day_id);

CREATE TABLE catalog_release (
  id smallint PRIMARY KEY DEFAULT 1 CONSTRAINT catalog_release_singleton CHECK (id = 1),
  version int NOT NULL DEFAULT 1,
  notes text,
  published_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO catalog_release (id, version, notes) VALUES (1, 1, 'initial') ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER workouts_set_updated_at BEFORE UPDATE ON workouts FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER saved_programs_set_updated_at BEFORE UPDATE ON saved_programs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER catalog_programs_set_updated_at BEFORE UPDATE ON catalog_programs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER user_progress_bundles_set_updated_at BEFORE UPDATE ON user_progress_bundles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW programs_including_exercise AS
SELECT
  e.id AS exercise_id,
  e.name AS exercise_name,
  e.name_key,
  cp.id AS program_id,
  cp.name AS program_name,
  cp.subtitle AS program_subtitle
FROM catalog_day_exercises cde
JOIN exercises e ON e.id = cde.exercise_id
JOIN catalog_program_days d ON d.id = cde.program_day_id
JOIN catalog_programs cp ON cp.id = d.program_id;

CREATE OR REPLACE VIEW admin_workouts_with_anomalies AS
SELECT DISTINCT w.id AS workout_id
FROM workouts w
JOIN workout_exercises we ON we.workout_id = w.id
WHERE trim(we.name) = ''
   OR NOT EXISTS (SELECT 1 FROM workout_sets ws0 WHERE ws0.exercise_id = we.id)
   OR EXISTS (
       SELECT 1 FROM workout_sets ws1
       WHERE ws1.exercise_id = we.id
         AND (ws1.reps <= 0 OR ws1.reps > 500 OR ws1.weight < 0 OR ws1.weight > 3000)
     );
