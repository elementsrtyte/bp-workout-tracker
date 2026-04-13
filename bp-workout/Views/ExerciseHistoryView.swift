import Charts
import SwiftData
import SwiftUI

struct ExerciseHistorySheetItem: Identifiable, Hashable {
    var id: String { ExerciseNameNormalizer.key(name) }
    let name: String
}

/// Weight history for one exercise (bundled data + your logs), with anomaly filtering from Settings.
struct ExerciseHistoryView: View {
    let exerciseName: String
    let loggedWorkouts: [LoggedWorkout]

    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var entries: [ProgressEntry] {
        Self.mergedCleanEntries(
            exerciseName: exerciseName,
            loggedWorkouts: loggedWorkouts,
            appSettings: appSettings
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if entries.isEmpty {
                    Text("No history for this exercise yet. Log a few sessions and it will show up here.")
                        .font(.subheadline)
                        .foregroundStyle(BlueprintTheme.mutedLight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                } else {
                    Text("\(entries.count) logged sets")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.mutedLight)

                    Chart {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                            if let d = ProgressMetrics.parseChartDate(e.date) {
                                LineMark(
                                    x: .value("Date", d),
                                    y: .value("Weight", e.weight)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(BlueprintTheme.purple)

                                PointMark(
                                    x: .value("Date", d),
                                    y: .value("Weight", e.weight)
                                )
                                .foregroundStyle(BlueprintTheme.lavender)
                            }
                        }
                    }
                    .chartYAxisLabel("lb", position: .trailing)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(BlueprintTheme.border)
                            AxisValueLabel()
                                .foregroundStyle(BlueprintTheme.mutedLight)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                                .foregroundStyle(BlueprintTheme.border)
                            AxisValueLabel()
                                .foregroundStyle(BlueprintTheme.mutedLight)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)

                    if let first = entries.first, let last = entries.last {
                        let peak = entries.map(\.weight).max() ?? first.weight
                        HStack {
                            miniStat(title: "First", value: formatWeight(first.weight))
                            Spacer()
                            miniStat(title: "Peak", value: formatWeight(peak))
                            Spacer()
                            miniStat(title: "Last", value: formatWeight(last.weight))
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(BlueprintTheme.bg)
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(BlueprintTheme.mutedLight)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BlueprintTheme.cream)
        }
    }

    private func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w)) lb" }
        return "\(w.formatted(.number.precision(.fractionLength(0...1)))) lb"
    }

    private static func mergedCleanEntries(
        exerciseName: String,
        loggedWorkouts: [LoggedWorkout],
        appSettings: AppSettings
    ) -> [ProgressEntry] {
        BundleDataStore.shared.loadIfNeeded()
        let key = ExerciseNameNormalizer.key(exerciseName)
        let user = LoggedWorkoutProgressExport.entriesByExerciseName(workouts: loggedWorkouts)

        let raw: [ProgressEntry]
        if let b = BundleDataStore.shared.progressBundle {
            let merged = ProgressMergeService.mergedExerciseProgress(bundle: b, userEntriesByExercise: user)
            if let ex = merged.first(where: { ExerciseNameNormalizer.key($0.name) == key }) {
                raw = ex.entries
            } else {
                raw = []
            }
        } else {
            raw = user.reduce(into: [ProgressEntry]()) { result, pair in
                if ExerciseNameNormalizer.key(pair.key) == key {
                    result.append(contentsOf: pair.value)
                }
            }
        }

        let sorted = raw.sorted { $0.date < $1.date }
        return AnomalyFilter.getCleanEntries(
            entries: sorted,
            filterEnabled: appSettings.filterAnomalies,
            sensitivity: appSettings.anomalySensitivity,
            minReps: appSettings.minReps
        )
        .sorted { $0.date < $1.date }
    }
}
