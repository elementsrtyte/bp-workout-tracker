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

## Configure API base URL

**Option A — dart-define (good for dev):**

```bash
flutter run --dart-define=BLUEPRINT_API_URL=http://127.0.0.1:8787
```

**Option B — `ios/Runner/Info.plist`:** add a string entry (same idea as the Swift `Info.plist`):

```xml
<key>BLUEPRINT_API_URL</key>
<string>http://127.0.0.1:8787</string>
```

The app reads `BLUEPRINT_API_URL` from `dart-define` first, then `Platform.environment`, then (if you wire it) Info.plist via a small native channel — **currently** only dart-define + environment are implemented in Dart; for Release builds prefer `--dart-define` or a config package.

## Run

```bash
flutter pub get
flutter run -d ios --dart-define=BLUEPRINT_API_URL=https://your-api-host
```

## Scope

This is a **scaffold**: tab shell, Blueprint theme, catalog fetch + models, placeholder screens. Port screens and Supabase auth from `bp-workout` incrementally.

## Related repo paths

- API: `../api`
- iOS reference: `../bp-workout`
