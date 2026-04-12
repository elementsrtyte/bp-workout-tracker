import SwiftData
import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject private var appSettings: AppSettings
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]

    var body: some View {
        NavigationStack {
            Form {
                Section("Minimum reps per set") {
                    Stepper(value: $appSettings.minReps, in: 1 ... 20) {
                        Text("\(appSettings.minReps) reps")
                    }
                    Text("Sets below this threshold are excluded from progress charts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("Sets excluded (estimate)") {
                        Text("\(viewModel.minRepsExcludedCount(loggedWorkouts: loggedWorkouts, appSettings: appSettings))")
                    }
                }

                Section("Anomaly filtering") {
                    Toggle("Filter outliers", isOn: $appSettings.filterAnomalies)
                    Picker("Sensitivity", selection: $appSettings.anomalySensitivity) {
                        Text("Low").tag(AnomalySensitivity.low)
                        Text("Medium").tag(AnomalySensitivity.medium)
                        Text("High").tag(AnomalySensitivity.high)
                    }
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

                Section {
                    Button("Reset settings to defaults", role: .destructive) {
                        appSettings.reset()
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .onChange(of: appSettings.filterAnomalies) { _, _ in appSettings.persist() }
        .onChange(of: appSettings.anomalySensitivity) { _, _ in appSettings.persist() }
        .onChange(of: appSettings.minReps) { _, _ in appSettings.persist() }
        .onAppear { viewModel.onAppear() }
    }
}
