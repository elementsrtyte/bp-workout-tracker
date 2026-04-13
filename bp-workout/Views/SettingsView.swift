import SwiftData
import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var auth: SupabaseSessionManager = .shared
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    Button("Sign out", role: .destructive) {
                        auth.signOut()
                    }
                    Text("Workout sync uses your Supabase account. Sign out on shared devices.")
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.mutedLight)
                }

                Section("Minimum reps per set") {
                    Stepper(value: $appSettings.minReps, in: 1 ... 20) {
                        Text("\(appSettings.minReps) reps")
                            .foregroundStyle(BlueprintTheme.cream)
                    }
                    Text("Sets below this threshold are excluded from progress charts.")
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.mutedLight)
                    LabeledContent("Sets excluded (estimate)") {
                        Text("\(viewModel.minRepsExcludedCount(loggedWorkouts: loggedWorkouts, appSettings: appSettings))")
                    }
                }

                Section("Anomaly filtering") {
                    Toggle("Filter outliers", isOn: $appSettings.filterAnomalies)
                    BlueprintMenuPicker(
                        title: "Sensitivity",
                        selection: $appSettings.anomalySensitivity,
                        options: AnomalySensitivity.allCases.map { ($0, $0.rawValue.capitalized) }
                    )
                    if appSettings.filterAnomalies {
                        LabeledContent("Flagged points (estimate)") {
                            Text("\(viewModel.anomalyFlaggedCount(loggedWorkouts: loggedWorkouts, appSettings: appSettings))")
                        }
                    }
                }

                Section("Logging") {
                    LabeledContent("Saved workouts") {
                        Text("\(loggedWorkouts.count)")
                    }
                }

                Section("Programs") {
                    Toggle("Program admin (publish catalog edits)", isOn: $appSettings.programAdminMode)
                    Text(
                        "Anyone can edit marketplace programs; those changes stay on this device. Turn this on only for development: saving a bundled program then updates the shared catalog for all users (API must allow your account)."
                    )
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.mutedLight)
                }

                Section("AI features") {
                    Text("Program import, exercise swap ideas, and related-exercise suggestions go through the Blueprint API. You must be signed in. The API URL is set in app configuration (BLUEPRINT_API_URL); OpenAI is used only on the server.")
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.mutedLight)
                }

                Section {
                    Button("Reset settings to defaults", role: .destructive) {
                        appSettings.reset()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BlueprintTheme.bg)
            .blueprintDismissKeyboardOnScroll()
            .navigationTitle("Settings")
            .tint(BlueprintTheme.purple)
        }
        .onChange(of: appSettings.filterAnomalies) { _, _ in appSettings.persist() }
        .onChange(of: appSettings.anomalySensitivity) { _, _ in appSettings.persist() }
        .onChange(of: appSettings.minReps) { _, _ in appSettings.persist() }
        .onChange(of: appSettings.programAdminMode) { _, _ in appSettings.persist() }
        .onAppear { viewModel.onAppear() }
    }
}
