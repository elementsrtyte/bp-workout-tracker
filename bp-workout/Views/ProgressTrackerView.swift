import Charts
import SwiftData
import SwiftUI

struct ProgressTrackerView: View {
    @StateObject private var viewModel = ProgressTrackerViewModel()
    @EnvironmentObject private var appSettings: AppSettings
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]

    @State private var searchPresented = false
    @State private var hasScrolledAwayFromTop = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chart")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                    BlueprintChipPicker(
                        title: "",
                        selection: $viewModel.chartMode,
                        options: ProgressChartMode.allCases.map { ($0, $0.pickerLabel) }
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ProgressScrollTopOffsetKey.self,
                            value: geo.frame(in: .named("progressScroll")).minY
                        )
                    }
                )

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
            .coordinateSpace(name: "progressScroll")
            .onPreferenceChange(ProgressScrollTopOffsetKey.self, perform: updateSearchVisibility(topOffset:))
            .frame(maxWidth: .infinity)
            .background(BlueprintTheme.bg)
            .navigationTitle("Progress")
            .searchable(text: $viewModel.search, isPresented: $searchPresented, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    BlueprintToolbarMenuPicker(
                        accessibilityLabel: "Sort exercises",
                        systemImage: "arrow.up.arrow.down",
                        selection: $viewModel.sortBy,
                        options: ProgressSortOption.allCases.map { ($0, $0.pickerLabel) }
                    )
                }
                ToolbarItem(placement: .secondaryAction) {
                    BlueprintToolbarMenuPicker(
                        accessibilityLabel: "Filter by program",
                        systemImage: "line.3.horizontal.decrease.circle",
                        selection: $viewModel.programFilter,
                        options: [("all", "All programs")]
                            + ProgressTrackerViewModel.programFilterOptions.map { ($0, $0) }
                    )
                }
            }
        }
        .onAppear { viewModel.onAppear() }
    }

    private var rows: [ProgressExerciseRow] {
        viewModel.filteredRows(loggedWorkouts: loggedWorkouts, appSettings: appSettings)
    }

    /// Reveal search when the user pulls down slightly or scrolls back near the top after browsing the list.
    private func updateSearchVisibility(topOffset: CGFloat) {
        if topOffset > 6 {
            if !searchPresented {
                searchPresented = true
            }
            return
        }
        if topOffset < -56 {
            if !hasScrolledAwayFromTop {
                hasScrolledAwayFromTop = true
            }
            if searchPresented {
                searchPresented = false
            }
            return
        }
        if hasScrolledAwayFromTop, topOffset > -24 {
            if !searchPresented {
                searchPresented = true
            }
        }
    }
}

private enum ProgressScrollTopOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ExerciseProgressCard: View {
    let row: ProgressExerciseRow
    let chartMode: ProgressChartMode
    let programColors: [String: String]

    @State private var scrubbedEntry: ProgressEntry?

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
        .onChange(of: chartMode) { _, _ in scrubbedEntry = nil }
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
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: trend == .up ? "arrow.up.right" : trend == .down ? "arrow.down.right" : "arrow.right")
                        Text("\(pct > 0 ? "+" : "")\(pct)%")
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    .foregroundStyle(trend == .up ? BlueprintTheme.mint : trend == .down ? BlueprintTheme.danger : BlueprintTheme.muted)
                    if let entry = scrubbedEntry {
                        headerScrubReadout(entry: entry)
                    }
                }
                .fixedSize(horizontal: true, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func headerScrubReadout(entry: ProgressEntry) -> some View {
        switch chartMode {
        case .weight:
            VStack(alignment: .trailing, spacing: 1) {
                Text(compactScrubDate(entry.date))
                    .font(.system(size: 10))
                    .foregroundStyle(BlueprintTheme.mutedLight)
                Text("\(formatWeight(entry.weight)) lb")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(BlueprintTheme.cream)
            }
        case .volume:
            let v = entry.weight * Double(entry.reps)
            VStack(alignment: .trailing, spacing: 1) {
                Text(compactScrubDate(entry.date))
                    .font(.system(size: 10))
                    .foregroundStyle(BlueprintTheme.mutedLight)
                Text("\(formatWeight(entry.weight))×\(entry.reps) · \(formatVol(v))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(BlueprintTheme.cream)
            }
        case .reprange:
            EmptyView()
        }
    }

    private func compactScrubDate(_ yyyyMMdd: String) -> String {
        guard let d = ProgressMetrics.parseChartDate(yyyyMMdd) else { return yyyyMMdd }
        return d.formatted(.dateTime.month(.abbreviated).day())
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
            InteractiveProgressLineChart(
                entries: cleanEntries,
                chartMode: chartMode,
                lineColor: { lineColor(for: $0) },
                scrubbedEntry: $scrubbedEntry
            )
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
                .foregroundStyle(BlueprintTheme.mutedLight.opacity(0.92))
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

// MARK: - Interactive line chart (weight / volume)

private struct InteractiveProgressLineChart: View {
    let entries: [ProgressEntry]
    let chartMode: ProgressChartMode
    let lineColor: (String) -> Color
    @Binding var scrubbedEntry: ProgressEntry?

    @State private var selectedX: Date?

    private var datedEntries: [(date: Date, entry: ProgressEntry)] {
        entries.compactMap { e in
            guard let d = ProgressMetrics.parseChartDate(e.date) else { return nil }
            return (d, e)
        }
        .sorted { $0.date < $1.date }
    }

    private func nearestEntry(to x: Date) -> ProgressEntry? {
        let pairs = datedEntries
        guard !pairs.isEmpty else { return nil }
        return pairs.min(by: { abs($0.date.timeIntervalSince(x)) < abs($1.date.timeIntervalSince(x)) })?.entry
    }

    var body: some View {
        Chart {
            ForEach(Array(datedEntries.enumerated()), id: \.offset) { _, pair in
                let d = pair.date
                let e = pair.entry
                if chartMode == .weight {
                    LineMark(
                        x: .value("Date", d),
                        y: .value("Weight", e.weight)
                    )
                    .foregroundStyle(lineColor(e.program))
                } else {
                    LineMark(
                        x: .value("Date", d),
                        y: .value("Volume", e.weight * Double(e.reps))
                    )
                    .foregroundStyle(BlueprintTheme.amber)
                }
            }

            if let x = selectedX, let entry = nearestEntry(to: x), let d = ProgressMetrics.parseChartDate(entry.date) {
                RuleMark(x: .value("Selected", x))
                    .foregroundStyle(BlueprintTheme.lavender.opacity(0.88))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                if chartMode == .weight {
                    PointMark(
                        x: .value("Date", d),
                        y: .value("Weight", entry.weight)
                    )
                    .symbolSize(72)
                    .foregroundStyle(BlueprintTheme.cream)
                } else {
                    let vol = entry.weight * Double(entry.reps)
                    PointMark(
                        x: .value("Date", d),
                        y: .value("Volume", vol)
                    )
                    .symbolSize(72)
                    .foregroundStyle(BlueprintTheme.cream)
                }
            }
        }
        .chartXSelection(value: $selectedX)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(BlueprintTheme.border.opacity(0.6))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(BlueprintTheme.mutedLight)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(BlueprintTheme.border.opacity(0.6))
                AxisValueLabel()
                    .foregroundStyle(BlueprintTheme.mutedLight)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
        .onChange(of: selectedX) { _, newX in
            scrubbedEntry = newX.flatMap { nearestEntry(to: $0) }
        }
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
                        .foregroundStyle(BlueprintTheme.mutedLight)
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
                        .foregroundStyle(BlueprintTheme.mutedLight)
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
