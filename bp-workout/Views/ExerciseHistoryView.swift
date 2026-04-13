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

                    ExerciseHistoryWeightChart(entries: entries)

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

// MARK: - Interactive weight chart (scrub)

private struct ExerciseHistoryWeightChart: View {
    let entries: [ProgressEntry]

    @State private var selectedX: Date?

    private var datedEntries: [(date: Date, entry: ProgressEntry)] {
        entries.compactMap { e in
            guard let d = ProgressMetrics.parseChartDate(e.date) else { return nil }
            return (d, e)
        }
        .sorted { $0.date < $1.date }
    }

    private func nearestEntry(to x: Date) -> ProgressEntry? {
        guard !datedEntries.isEmpty else { return nil }
        return datedEntries.min(by: { abs($0.date.timeIntervalSince(x)) < abs($1.date.timeIntervalSince(x)) })?.entry
    }

    private var selectedEntry: ProgressEntry? {
        guard let x = selectedX else { return nil }
        return nearestEntry(to: x)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(Array(datedEntries.enumerated()), id: \.offset) { _, pair in
                    let d = pair.date
                    let e = pair.entry
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
                    .symbolSize(36)
                    .foregroundStyle(BlueprintTheme.lavender.opacity(0.9))
                }

                if let x = selectedX, let entry = nearestEntry(to: x), let d = ProgressMetrics.parseChartDate(entry.date) {
                    RuleMark(x: .value("Selected", x))
                        .foregroundStyle(BlueprintTheme.lavender.opacity(0.88))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    PointMark(
                        x: .value("Date", d),
                        y: .value("Weight", entry.weight)
                    )
                    .symbolSize(88)
                    .foregroundStyle(BlueprintTheme.cream)
                }
            }
            .chartXSelection(value: $selectedX)
            .chartYAxisLabel("lb", position: .trailing)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(BlueprintTheme.border.opacity(0.6))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(BlueprintTheme.mutedLight)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(BlueprintTheme.border.opacity(0.6))
                    AxisValueLabel()
                        .foregroundStyle(BlueprintTheme.mutedLight)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)

            scrubReadoutStrip

            Text("Drag along the chart to see weight and date.")
                .font(.caption2)
                .foregroundStyle(BlueprintTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scrubReadoutStrip: some View {
        Group {
            if let entry = selectedEntry {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "scope")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.lavender)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scrubPrimaryLine(entry))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.cream)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(entry.reps > 0 ? "\(entry.reps) reps · \(entry.program)" : entry.program)
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 52, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BlueprintTheme.cardInner)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BlueprintTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Color.clear
                    .frame(height: 52)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
        }
    }

    private func scrubPrimaryLine(_ entry: ProgressEntry) -> String {
        let dateStr = scrubDateString(entry.date)
        let w = formatScrubWeight(entry.weight)
        return "\(dateStr) · \(w)"
    }

    private func scrubDateString(_ yyyyMMdd: String) -> String {
        guard let d = ProgressMetrics.parseChartDate(yyyyMMdd) else { return yyyyMMdd }
        return Self.scrubDF.string(from: d)
    }

    private func formatScrubWeight(_ w: Double) -> String {
        if w == floor(w) { return "\(Int(w)) lb" }
        return "\(w.formatted(.number.precision(.fractionLength(0...1)))) lb"
    }

    private static let scrubDF: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}
