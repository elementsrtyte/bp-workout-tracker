# bp_workout_flutter

Flutter **iOS** client for Blueprint Workout, calling the same **Blueprint API** as the Swift app (`BLUEPRINT_API_URL`, e.g. `GET /v1/catalog/programs`).

## Your answers (from planning)

| Topic | Choice |
|--------|--------|
| Milestone | Core parity (tabs: Workout, Progress, Calendar, Programs, Settings) |
| Platforms | iOS only (v1) |
| State | Riverpod (chosen for you) |
| Local data | `sqflite` + `flutter_secure_storage` (simple structured cache; no Drift codegen in repo yet) |
| UI | Match Blueprint theme (dark + purple accent) |

## Prerequisites

- Flutter SDK (stable), Xcode for iOS builds.

## One-time project bootstrap

This folder ships **Dart sources + `pubspec.yaml`**. Generate the iOS runner if you don’t have it yet:

```bash
cd bp_workout_flutter
flutter create --platforms=ios --org com.blueprint.bpworkout --project-name bp_workout_flutter .
```

If `ios/` already exists, you can instead run:

```bash
flutter pub get
```

## Configure API + Supabase (`.env.local`, like `api/`)

**iOS/Android:** create **`bp_workout_flutter/.env.local`** (it is a **pubspec asset**, so it is packaged into the app). The simulator does not use your repo folder as the process working directory, so reading only `File('.env.local')` from disk does not work there.

```bash
cd bp_workout_flutter
cp .env.example .env.local
# Edit .env.local with SUPABASE_URL, SUPABASE_ANON_KEY, BLUEPRINT_API_URL
flutter pub get
```

Optional **`.env`** on disk is merged before `.env.local` (useful on desktop or when the project path is found via `PWD` / monorepo layout).

**Precedence (highest first):**

1. `--dart-define=KEY=value` or `--dart-define-from-file=path/to.env` (best for CI / release)
2. Exported shell environment variables
3. **`.env`**, then **`.env.local`** from disk (search includes repo root + `bp_workout_flutter/`)
4. Bundled **`.env.local`** on **iOS/Android** only
5. **`.env.example`**

You can run without env files by passing defines only:

```bash
flutter run --dart-define=BLUEPRINT_API_URL=http://127.0.0.1:8787
```

**Security:** Do not put production secrets in **`.env.example`**. Treat **`.env.local`** like `api/.env.local`.

## Run

```bash
flutter pub get
# Prefer a local .env (see above); or pass defines:
flutter run -d "<simulator-id-or-name>" \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key \
  --dart-define=BLUEPRINT_API_URL=https://your-api-host
```

See **`PARITY.md`** for native vs Flutter feature checklist.

## Scope

Scaffold + auth gate + program library keys; full UI parity is tracked in `PARITY.md`.

## Related repo paths

- API: `../api`
- iOS reference: `../bp-workout`
