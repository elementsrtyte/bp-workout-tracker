# Native iOS → Flutter parity

**Goal:** Same product behavior as `bp-workout` (Swift + SwiftData + Supabase + Blueprint API).

**Reality:** The Swift app is large (multi‑thousand LOC across `HomeView`, `ProgramEditorView`, workout logging, AI clients, notifications, etc.). **Exact parity is a phased project**, not a single commit. This file tracks what exists in Flutter vs iOS.

## Legend

- **Done** — implemented in Flutter (may still differ in UI polish).
- **Partial** — subset only.
- **Todo** — not started.

## App shell

| Area | iOS | Flutter |
|------|-----|---------|
| Dark mode + Blueprint colors | `bp_workoutApp` + `BlueprintTheme` | **Done** (`blueprint_theme.dart`) |
| Auth gate (no device-only accounts) | `AuthRootView` | **Partial** (`auth_shell.dart` — sign-in / sign-up / forgot password; password-reset deep link **Todo**) |
| 5 tabs | `RootView` | **Done** (`main_shell.dart`) |
| Catalog refresh on launch | `RootView.task` | **Todo** (wire `BundleDataStore`-equivalent) |
| Bundled program update alert | `RootView` alert | **Todo** |

## Auth (Supabase GoTrue)

| Feature | iOS | Flutter |
|---------|-----|---------|
| Config: `SUPABASE_URL`, `SUPABASE_ANON_KEY` | `SupabaseConfig` | **Done** (`env.dart` + dart-define) |
| Sign in / sign up / forgot password | `AuthFlowViews` | **Partial** (email/password flows; magic-link / session from redirect **Todo**) |
| Saved email | `supabase.saved.email` | **Done** (`AuthConstants.supabaseSavedEmailKey` + `shared_preferences`) |
| Keychain session | `KeychainStore` | **Handled by** `supabase_flutter` secure persistence |
| `onOpenURL` recovery | `bp_workoutApp` | **Todo** (`app_links` / uni_links) |

## Programs / marketplace

| Feature | iOS | Flutter |
|---------|-----|---------|
| `GET /v1/catalog/programs` | `BlueprintCatalogFetcher` | **Done** |
| Models (programs, categories, stats) | `WorkoutProgramModels` | **Done** |
| Profile library (defaults = all) | `UserProgramLibrary` | **Partial** (same keys; `user_program_library.dart`) |
| Marketplace UI (grid, shelves, chips, …) | `ProgramMarketplaceView` | **Todo** (list + add/remove profile only) |
| Custom programs + editor | `ProgramEditorView` + disk JSON | **Todo** |
| Import program (AI) | `ImportProgramTextView` + API | **Todo** |
| Admin catalog publish | `POST /v1/admin/catalog/programs` | **Todo** |

## Workout hub & logging

| Feature | iOS | Flutter |
|---------|-----|---------|
| SwiftData: `LoggedWorkout` / Exercise / Set | `LoggedWorkoutModels` | **Partial** (`sqflite` v2: `logged_workouts` / exercises / sets) |
| Hub UI + day picker | `HomeView` / `WorkoutHubViewModel` | **Partial** (program + day chips + recent list) |
| Log workout flows | `LogWorkoutViews` | **Partial** (per-set weight/reps from prescription) |
| `POST /v1/workouts` sync | `SupabaseWorkoutPushClient` | **Partial** (Bearer + same JSON shape; errors surfaced if offline) |
| Substitutions / AI | OpenAI clients | **Todo** |
| Rest timer / notifications | `RestTimerNotificationScheduler` | **Todo** |

## Progress

| Feature | iOS | Flutter |
|---------|-----|---------|
| Charts / PRs | `ProgressTrackerView` | **Todo** |
| Exercise history | `ExerciseHistoryView` | **Todo** |
| Progress JSON merge | `ProgressMergeService` + bundle | **Todo** |

## Calendar

| Feature | iOS | Flutter |
|---------|-----|---------|
| Gym calendar | `GymCalendarView` | **Todo** |

## Settings

| Feature | iOS | Flutter |
|---------|-----|---------|
| `AppSettings` persistence | `UserDefaults` JSON | **Todo** |
| Settings UI | `SettingsView` | **Todo** (partial: API URL line only) |

## How to run with parity-related env (match iOS Info.plist)

```bash
flutter run -d "<simulator>" \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your_anon_key \
  --dart-define=BLUEPRINT_API_URL=https://your-api-host
```

## Suggested implementation order

1. Auth + deep links + session edge cases  
2. Local workout DB + hub + API sync  
3. Programs marketplace UI parity + custom programs + import  
4. Progress + calendar  
5. Settings + notifications + polish

Update this table as features land.
