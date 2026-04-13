import Charts
import SwiftData
import SwiftUI

struct ProgressTrackerView: View {
    @StateObject private var viewModel = ProgressTrackerViewModel()
    @EnvironmentObject private var appSettings: AppSettings
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chart")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                    Picker("Chart mode", selection: $viewModel.chartMode) {
                        Text("Weight").tag(ProgressChartMode.weight)
                        Text("Volume").tag(ProgressChartMode.volume)
                        Text("Reps").tag(ProgressChartMode.reprange)
                    }
                    .pickerStyle(.menu)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                LazyVStack(spacing: 12) {
                    ForEach(rows) { row in
                        ExerciseProgressCard(
                            row: row,
                            chartMode: viewModel.chartMode,
                            programColors: viewModel.mergedProgramColors()
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(BlueprintTheme.bg)
            .navigationTitle("Progress")
            .searchable(text: $viewModel.search, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu("Sort") {
                        Picker("Sort", selection: $viewModel.sortBy) {
                            Text("Most sessions").tag(ProgressSortOption.sessions)
                            Text("Biggest gain").tag(ProgressSortOption.gain)
                            Text("Heaviest peak").tag(ProgressSortOption.peak)
                            Text("A–Z").tag(ProgressSortOption.alpha)
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu("Program") {
                        Picker("Program", selection: $viewModel.programFilter) {
                            Text("All programs").tag("all")
                            ForEach(ProgressTrackerViewModel.programFilterOptions, id: \.self) { p in
                                Text(p).tag(p)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { viewModel.onAppear() }
    }

    private var rows: [ProgressExerciseRow] {
        viewModel.filteredRows(loggedWorkouts: loggedWorkouts, appSettings: appSettings)
    }
}

private struct ExerciseProgressCard: View {
    let row: ProgressExerciseRow
    let chartMode: ProgressChartMode
    let programColors: [String: String]

    private var ex: ExerciseProgress { row.exercise }
    private var cleanEntries: [ProgressEntry] { row.cleanEntries }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chartArea
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ex.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.cream)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text("\(cleanEntries.count) points")
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.muted)
                    if row.removedCount > 0 {
                        Text("\(row.removedCount) filtered")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BlueprintTheme.amber.opacity(0.15))
                            .foregroundStyle(BlueprintTheme.amber)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if chartMode != .reprange {
                let pct = chartMode == .volume
                    ? ProgressMetrics.volumePctChange(entries: cleanEntries)
                    : ProgressMetrics.pctChange(entries: cleanEntries)
                let trend = ProgressMetrics.trend(entries: cleanEntries)
                HStack(spacing: 4) {
                    Image(systemName: trend == .up ? "arrow.up.right" : trend == .down ? "arrow.down.right" : "arrow.right")
                    Text("\(pct > 0 ? "+" : "")\(pct)%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }
                .foregroundStyle(trend == .up ? BlueprintTheme.mint : trend == .down ? BlueprintTheme.danger : BlueprintTheme.muted)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    @ViewBuilder
    private var chartArea: some View {
        if cleanEntries.isEmpty {
            Text("All entries filtered")
                .font(.caption)
                .foregroundStyle(BlueprintTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 80)
        } else if chartMode == .reprange {
            RepRangeBars(entries: cleanEntries)
                .frame(height: 90)
        } else {
            Chart {
                ForEach(Array(cleanEntries.enumerated()), id: \.offset) { _, e in
                    if let d = ProgressMetrics.parseChartDate(e.date) {
                        if chartMode == .weight {
                            LineMark(
                                x: .value("Date", d),
                                y: .value("Weight", e.weight)
                            )
                            .foregroundStyle(lineColor(for: e.program))
                        } else {
                            LineMark(
                                x: .value("Date", d),
                                y: .value("Volume", e.weight * Double(e.reps))
                            )
                            .foregroundStyle(BlueprintTheme.amber)
                        }
                    }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(maxWidth: .infinity)
            .frame(height: 90)
        }
    }

    private func lineColor(for program: String) -> Color {
        let hex = programColors[program] ?? "#3ecf8e"
        return Color(hex: hex)
    }

    private var footer: some View {
        Group {
            if chartMode == .weight, let first = cleanEntries.first, let last = cleanEntries.last {
                let peak = cleanEntries.map(\.weight).max() ?? first.weight
                HStack {
                    miniStat(title: "Start", value: formatWeight(first.weight), color: BlueprintTheme.mutedLight)
                    Spacer()
                    miniStat(title: "Peak", value: formatWeight(peak), color: BlueprintTheme.mint)
                    Spacer()
                    miniStat(title: "Last", value: formatWeight(last.weight), color: BlueprintTheme.mutedLight)
                }
                .font(.caption2)
            } else if chartMode == .volume, let first = cleanEntries.first, let last = cleanEntries.last {
                let fv = first.weight * Double(first.reps)
                let lv = last.weight * Double(last.reps)
                let pk = cleanEntries.map { $0.weight * Double($0.reps) }.max() ?? fv
                HStack {
                    miniStat(title: "Start", value: formatVol(fv), color: BlueprintTheme.mutedLight)
                    Spacer()
                    miniStat(title: "Peak", value: formatVol(pk), color: BlueprintTheme.amber)
                    Spacer()
                    miniStat(title: "Last", value: formatVol(lv), color: BlueprintTheme.mutedLight)
                }
                .font(.caption2)
            } else if chartMode == .reprange {
                let rows = ProgressMetrics.repRangeCounts(entries: cleanEntries).filter { $0.count > 0 }
                FlowRow(items: rows)
            }
        }
    }

    private func miniStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .foregroundStyle(BlueprintTheme.muted)
            Text(value)
                .foregroundStyle(color)
                .fontWeight(.semibold)
        }
    }

    private func formatWeight(_ w: Double) -> String {
        w.formatted(.number.precision(.fractionLength(0...1)))
    }

    private func formatVol(_ v: Double) -> String {
        Int(v).formatted()
    }
}

private struct RepRangeBars: View {
    let entries: [ProgressEntry]

    var body: some View {
        let data = ProgressMetrics.repRangeCounts(entries: entries)
        let total = data.map(\.count).reduce(0, +)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(data, id: \.bucket.label) { pair in
                VStack(spacing: 2) {
                    GeometryReader { g in
                        let h = total > 0 ? CGFloat(pair.count) / CGFloat(total) * g.size.height : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(pair.count > 0 ? Color(hex: pair.bucket.colorHex) : BlueprintTheme.border)
                            .frame(height: max(h, pair.count > 0 ? 8 : 2))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .frame(maxWidth: .infinity)
                    Text(pair.bucket.label)
                        .font(.system(size: 9))
                        .foregroundStyle(BlueprintTheme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FlowRow: View {
    let items: [(bucket: ProgressMetrics.RepBucket, count: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items, id: \.bucket.label) { pair in
                HStack(alignment: .top, spacing: 6) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: pair.bucket.colorHex))
                        .frame(width: 6, height: 6)
                        .padding(.top, 2)
                    Text(pair.bucket.description)
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(pair.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color(hex: pair.bucket.colorHex))
                        .fixedSize(horizontal: true, vertical: false)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
