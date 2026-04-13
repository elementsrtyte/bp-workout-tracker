import SwiftData
import SwiftUI

/// Primary screen: day-first logging; program changes rarely and stays in a compact picker.
struct WorkoutHubView: View {
    @StateObject private var viewModel = WorkoutHubViewModel()
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var programLibrary: UserProgramLibrary
    @ObservedObject private var bundleData = BundleDataStore.shared

    @State private var showProgramTargets = false
    @State private var showIncompleteSaveConfirm = false
    @State private var exerciseHistoryItem: ExerciseHistorySheetItem?
    @State private var substitutionRoute: ExerciseSubstitutionSheetRoute?

    private var catalogExerciseNames: [String] {
        bundleData.mergedPrograms.flatMap(\.days).flatMap(\.exercises).map(\.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !viewModel.programs.isEmpty {
                    dayHeaderAndQuickLog
                } else {
                    emptyProfileProgramsCallout
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .background(BlueprintTheme.bg)
        .navigationTitle(viewModel.activeDay?.label ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            finishSessionBar
        }
        .blueprintDismissKeyboardOnScroll()
        .sheet(item: $exerciseHistoryItem) { item in
            NavigationStack {
                ExerciseHistoryView(exerciseName: item.name, loggedWorkouts: loggedWorkouts)
                    .environmentObject(appSettings)
            }
            .tint(BlueprintTheme.purple)
        }
        .onAppear {
            viewModel.onAppear()
            viewModel.syncLoggedWorkouts(loggedWorkouts)
        }
        .onChange(of: loggedWorkouts.count) { _, _ in
            viewModel.syncLoggedWorkouts(loggedWorkouts)
        }
        .onChange(of: programLibrary.updateCounter) { _, _ in
            viewModel.onLibraryChanged()
        }
        .onChange(of: bundleData.userProgramsRevision) { _, _ in
            viewModel.onCatalogChanged()
        }
        .confirmationDialog(
            "Workout not finished",
            isPresented: $showIncompleteSaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Save anyway", role: .destructive) {
                viewModel.finishAndSave(modelContext: modelContext)
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(viewModel.incompleteSaveAlertMessage)
        }
        .sheet(item: $substitutionRoute) { route in
            ExerciseSubstitutionSheet(
                prescribedName: route.prescribedName,
                currentName: route.currentName,
                rowId: route.rowId,
                hasLoggedSets: route.hasLoggedSets,
                catalogExerciseNames: catalogExerciseNames,
                viewModel: viewModel
            )
        }
    }

    private var emptyProfileProgramsCallout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No programs in your profile")
                .font(.headline)
                .foregroundStyle(BlueprintTheme.cream)
            Text("Open the Programs tab, pick a plan, and tap Add to profile. It will show up here for quick logging.")
                .font(.subheadline)
                .foregroundStyle(BlueprintTheme.mutedLight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private var dayHeaderAndQuickLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = viewModel.activeProgram {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Program")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
                        Spacer(minLength: 0)
                        if p.isUserCreated == true {
                            Text("SELF-CREATED")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BlueprintTheme.mint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BlueprintTheme.mint.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    BlueprintMenuPicker(
                        title: "",
                        selection: Binding(
                            get: { viewModel.activeProgramId },
                            set: { viewModel.selectProgram(id: $0) }
                        ),
                        options: viewModel.programs.map { ($0.id, $0.name) }
                    )
                    .padding(.horizontal, 20)

                    if !p.subtitle.isEmpty {
                        Text(p.subtitle)
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.muted)
                            .padding(.horizontal, 20)
                    }

                    WeeklyStreakTeaser(
                        snapshot: WorkoutWeeklyStreakEngine.snapshot(
                            loggedWorkouts: loggedWorkouts,
                            activeProgram: viewModel.activeProgram
                        )
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Training day")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.lavender)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)

                    BlueprintChipPicker(
                        title: "",
                        selection: Binding(
                            get: { viewModel.dayIndex },
                            set: { viewModel.setDayIndex($0) }
                        ),
                        options: Array(p.days.enumerated()).map { i, day in
                            let label = day.label.trimmingCharacters(in: .whitespacesAndNewlines)
                            return (i, label.isEmpty ? "Day \(i + 1)" : label)
                        }
                    )
                    .padding(.horizontal, 20)

                    if viewModel.dayIndex < p.days.count {
                        let day = p.days[viewModel.dayIndex]
                        lastCompletedTrainingDayLine(program: p, day: day)
                    }

                    if viewModel.dayIndex < p.days.count {
                        let day = p.days[viewModel.dayIndex]
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Today's session")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BlueprintTheme.lavender)
                                .padding(.horizontal, 20)
                                .padding(.top, 4)

                            ForEach(quickLogSegments(rows: viewModel.exerciseRows)) { segment in
                                switch segment {
                                case .single(let row):
                                    QuickLogExerciseCard(
                                        row: row,
                                        viewModel: viewModel,
                                        chrome: .standalone,
                                        onHistory: { exerciseHistoryItem = ExerciseHistorySheetItem(name: row.name) },
                                        onSwapExercise: {
                                            substitutionRoute = ExerciseSubstitutionSheetRoute(
                                                rowId: row.id,
                                                prescribedName: row.prescribedName,
                                                currentName: row.name,
                                                hasLoggedSets: !row.loggedSets.isEmpty
                                            )
                                        }
                                    )
                                case .supersetBlock(let group, let rows):
                                    SupersetQuickLogBlock(
                                        group: group,
                                        rows: rows,
                                        viewModel: viewModel,
                                        onHistory: { exerciseHistoryItem = ExerciseHistorySheetItem(name: $0) },
                                        onSwapExercise: { row in
                                            substitutionRoute = ExerciseSubstitutionSheetRoute(
                                                rowId: row.id,
                                                prescribedName: row.prescribedName,
                                                currentName: row.name,
                                                hasLoggedSets: !row.loggedSets.isEmpty
                                            )
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 12)

                            DisclosureGroup(isExpanded: $showProgramTargets) {
                                ExerciseTable(day: day)
                                    .padding(.top, 8)
                            } label: {
                                Text("Program targets (reference)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.mutedLight)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, viewModel.hasLoggedSomething ? 100 : 24)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lastCompletedTrainingDayLine(program: WorkoutProgram, day: WorkoutDay) -> some View {
        let lastDate = loggedWorkouts.first { w in
            w.programName == program.name && w.dayLabel == day.label
        }?.date

        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.caption)
                .foregroundStyle(BlueprintTheme.mint.opacity(0.95))
            if let lastDate {
                Text("Last completed \(lastDate.formatted(.dateTime.month(.abbreviated).day().year().hour().minute()))")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.mutedLight)
            } else {
                Text("You haven’t completed this training day yet.")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.muted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 2)
    }

    private var finishSessionBar: some View {
        VStack(spacing: 8) {
            Button {
                if viewModel.hasIncompletePlannedWork {
                    showIncompleteSaveConfirm = true
                } else {
                    viewModel.finishAndSave(modelContext: modelContext)
                }
            } label: {
                Label("Save workout", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(BlueprintTheme.purple)
            .disabled(!viewModel.hasLoggedSomething)

            if viewModel.hasLoggedSomething {
                Text("Saves all logged sets for this day in one entry.")
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(BlueprintTheme.bg.opacity(0.92))
    }
}

// MARK: - Quick log segments (superset runs)

private struct ExerciseSubstitutionSheetRoute: Identifiable {
    var id: String { rowId }
    let rowId: String
    let prescribedName: String
    let currentName: String
    let hasLoggedSets: Bool
}

private enum QuickLogSegment: Identifiable {
    case single(QuickExerciseState)
    case supersetBlock(group: Int, rows: [QuickExerciseState])

    var id: String {
        switch self {
        case .single(let r): return r.id
        case .supersetBlock(_, let rows): return rows.map(\.id).joined(separator: "|")
        }
    }
}

private func quickLogSegments(rows: [QuickExerciseState]) -> [QuickLogSegment] {
    var out: [QuickLogSegment] = []
    var i = 0
    while i < rows.count {
        let r = rows[i]
        guard let g = r.supersetGroup else {
            out.append(.single(r))
            i += 1
            continue
        }
        var run: [QuickExerciseState] = [r]
        var j = i + 1
        while j < rows.count, rows[j].supersetGroup == g {
            run.append(rows[j])
            j += 1
        }
        if run.count > 1 {
            out.append(.supersetBlock(group: g, rows: run))
        } else {
            out.append(.single(r))
        }
        i = j
    }
    return out
}

// MARK: - Superset quick log block

private struct SupersetQuickLogBlock: View {
    let group: Int
    let rows: [QuickExerciseState]
    @ObservedObject var viewModel: WorkoutHubViewModel
    var onHistory: (String) -> Void
    var onSwapExercise: (QuickExerciseState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Superset")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BlueprintTheme.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BlueprintTheme.amber.opacity(0.22))
                    .clipShape(Capsule())
                Text("Group \(group)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.mutedLight)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BlueprintTheme.amber.opacity(0.08))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(BlueprintTheme.amber.opacity(0.85))
                    .frame(width: 4)
                    .padding(.leading, 6)
                    .padding(.vertical, 10)

                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        QuickLogExerciseCard(
                            row: row,
                            viewModel: viewModel,
                            chrome: .supersetGroupedRow,
                            onHistory: { onHistory(row.name) },
                            onSwapExercise: { onSwapExercise(row) }
                        )
                        if i < rows.count - 1 {
                            Divider()
                                .background(BlueprintTheme.amber.opacity(0.25))
                                .padding(.leading, 18)
                        }
                    }
                }
                .padding(.leading, 18)
            }
        }
        .background(BlueprintTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(BlueprintTheme.amber.opacity(0.4), lineWidth: 1)
        )
    }
}

// MARK: - Quick log row

private enum QuickLogCardChrome: Equatable {
    /// Normal card with border; optional lone “Superset” pill when `row.supersetGroup != nil`.
    case standalone
    /// Row inside `SupersetQuickLogBlock` (shared chrome; no per-row border).
    case supersetGroupedRow
}

private struct QuickLogExerciseCard: View {
    let row: QuickExerciseState
    @ObservedObject var viewModel: WorkoutHubViewModel
    var chrome: QuickLogCardChrome = .standalone
    var onHistory: () -> Void
    var onSwapExercise: () -> Void

    var body: some View {
        let inner = VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(BlueprintTheme.mint)
                    .frame(width: 6, height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.cream)
                            .fixedSize(horizontal: false, vertical: true)
                        if chrome == .standalone, row.supersetGroup != nil {
                            Text("Superset")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BlueprintTheme.amber)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(BlueprintTheme.amber.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        if row.isAmrap {
                            Text("AMRAP")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BlueprintTheme.mint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BlueprintTheme.mint.opacity(0.18))
                                .clipShape(Capsule())
                        }
                        if row.isWarmup {
                            Text("WARM-UP")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(BlueprintTheme.mutedLight)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BlueprintTheme.cardInner)
                                .overlay(Capsule().stroke(BlueprintTheme.border, lineWidth: 1))
                                .clipShape(Capsule())
                        }
                    }
                    if row.isSubstituted {
                        Text("Substituted · prescribed: \(row.prescribedName)")
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        if let hint = row.prHint {
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(BlueprintTheme.lavender)
                        }
                        Text("Plan: \(row.planDisplay)")
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.muted)
                    }
                    if let note = row.programNotes {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text("\(row.loggedSets.count) / \(row.targetSets) sets")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(row.isSetsComplete ? BlueprintTheme.mint : BlueprintTheme.muted)
                }
                Spacer(minLength: 0)
                Button(action: onHistory) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.body.weight(.medium))
                        .foregroundStyle(BlueprintTheme.lavender)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("History for \(row.name)")
            }

            HStack(spacing: 8) {
                nudgeChip(title: "Wt", value: weightLabel, minus: { viewModel.nudgeWeight(for: row.id, delta: -2.5) }, plus: { viewModel.nudgeWeight(for: row.id, delta: 2.5) })
                nudgeChip(
                    title: row.isAmrap ? "Reps (AMRAP)" : "Reps",
                    value: "\(row.workingReps)",
                    minus: { viewModel.nudgeReps(for: row.id, delta: -1) },
                    plus: { viewModel.nudgeReps(for: row.id, delta: 1) }
                )
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.logSet(for: row.id)
                } label: {
                    Text(row.isSetsComplete ? "All sets logged" : "Log set \(row.loggedSets.count + 1) of \(row.targetSets)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BlueprintTheme.purple)
                .disabled(row.isSetsComplete)

                Button {
                    viewModel.repeatLastSet(for: row.id)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(row.loggedSets.isEmpty || row.isSetsComplete)
                .accessibilityLabel("Repeat last set")

                Menu {
                    Button("Swap exercise…") {
                        onSwapExercise()
                    }
                    Button("Undo last set", role: .destructive) {
                        viewModel.removeLastSet(for: row.id)
                    }
                    .disabled(row.loggedSets.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
            }

            if !row.loggedSets.isEmpty {
                FlowSetChips(sets: row.loggedSets, targetSets: row.targetSets)
            }
        }

        switch chrome {
        case .standalone:
            inner
                .padding(12)
                .background(BlueprintTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BlueprintTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .supersetGroupedRow:
            inner
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
        }
    }

    private var weightLabel: String {
        if row.workingWeight == 0 { return "BW" }
        return WorkoutPrefill.formatWeight(row.workingWeight)
    }

    private func nudgeChip(title: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            HStack(spacing: 4) {
                Button(action: minus) {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(BlueprintTheme.cream)
                    .frame(minWidth: 44)
                Button(action: plus) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FlowSetChips: View {
    let sets: [LoggedSetSnapshot]
    let targetSets: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Logged")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(sets.enumerated()), id: \.offset) { i, s in
                    Text(chipLabel(setIndex: i + 1, s))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(BlueprintTheme.cream)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(BlueprintTheme.purple.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func chipLabel(setIndex: Int, _ s: LoggedSetSnapshot) -> String {
        let core: String
        if s.weight == 0 { core = "BW×\(s.reps)" }
        else { core = "\(WorkoutPrefill.formatWeight(s.weight))×\(s.reps)" }
        if targetSets > 1 { return "\(setIndex). \(core)" }
        return core
    }
}

// MARK: - Reference table

private enum ExerciseTableSegment: Identifiable {
    case single(Exercise)
    case supersetBlock(group: Int, exercises: [Exercise])

    var id: String {
        switch self {
        case .single(let e): return e.id
        case .supersetBlock(_, let ex): return ex.map(\.id).joined(separator: "|")
        }
    }
}

private func exerciseTableSegments(exercises: [Exercise]) -> [ExerciseTableSegment] {
    var out: [ExerciseTableSegment] = []
    var i = 0
    while i < exercises.count {
        let e = exercises[i]
        guard let g = e.supersetGroup else {
            out.append(.single(e))
            i += 1
            continue
        }
        var run: [Exercise] = [e]
        var j = i + 1
        while j < exercises.count, exercises[j].supersetGroup == g {
            run.append(exercises[j])
            j += 1
        }
        if run.count > 1 {
            out.append(.supersetBlock(group: g, exercises: run))
        } else {
            out.append(.single(e))
        }
        i = j
    }
    return out
}

private struct ExerciseTable: View {
    let day: WorkoutDay

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Exercise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Sets")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.muted)
                    .frame(width: 36, alignment: .trailing)
                Text("Max weight")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(BlueprintTheme.cardInner)

            ForEach(exerciseTableSegments(exercises: day.exercises)) { segment in
                switch segment {
                case .single(let ex):
                    exerciseTableRow(ex: ex, supersetChrome: .standalone)
                    Divider().background(BlueprintTheme.border)
                case .supersetBlock(let group, let exercises):
                    ExerciseTableSupersetBlock(group: group, exercises: exercises)
                    Divider().background(BlueprintTheme.border)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private enum ExerciseRowSupersetChrome {
        case standalone
        case groupedRow
    }

    @ViewBuilder
    private func exerciseTableRow(ex: Exercise, supersetChrome: ExerciseRowSupersetChrome) -> some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(BlueprintTheme.mint)
                    .frame(width: 6, height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.name)
                        .font(.subheadline)
                        .foregroundStyle(BlueprintTheme.cream)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if supersetChrome == .standalone, ex.supersetGroup != nil {
                        Text("Superset")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BlueprintTheme.amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(BlueprintTheme.amber.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    if ex.prescriptionIsAmrap || ex.prescriptionIsWarmup {
                        HStack(spacing: 6) {
                            if ex.prescriptionIsAmrap {
                                Text("AMRAP")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.mint)
                            }
                            if ex.prescriptionIsWarmup {
                                Text("Warm-up")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.mutedLight)
                            }
                        }
                    }
                    if let note = ex.trimmedProgramNotes {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            Text("\(ex.prescribedSets)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.mutedLight)
                .frame(width: 36, alignment: .trailing)

            Group {
                let plan = ex.maxWeight.trimmingCharacters(in: .whitespacesAndNewlines)
                if plan.isEmpty {
                    Text("—")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                } else {
                    Text(plan)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isBodyweight(plan) ? BlueprintTheme.muted : BlueprintTheme.lavender)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(planMaxChipBackground(ex.maxWeight))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .layoutPriority(1)
            .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(BlueprintTheme.card)
    }

    private func isBodyweight(_ s: String) -> Bool {
        s.lowercased().contains("bodyweight")
    }

    private func planMaxChipBackground(_ raw: String) -> Color {
        let plan = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if plan.isEmpty || isBodyweight(plan) {
            return Color.white.opacity(0.05)
        }
        return BlueprintTheme.purple.opacity(0.12)
    }
}

private struct ExerciseTableSupersetBlock: View {
    let group: Int
    let exercises: [Exercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Superset")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BlueprintTheme.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BlueprintTheme.amber.opacity(0.22))
                    .clipShape(Capsule())
                Text("Group \(group)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.mutedLight)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BlueprintTheme.amber.opacity(0.08))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(BlueprintTheme.amber.opacity(0.85))
                    .frame(width: 4)
                    .padding(.leading, 6)
                    .padding(.vertical, 8)

                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { i, ex in
                        ExerciseTableSupersetBlockRow(ex: ex)
                        if i < exercises.count - 1 {
                            Divider()
                                .background(BlueprintTheme.amber.opacity(0.25))
                                .padding(.leading, 18)
                        }
                    }
                }
                .padding(.leading, 18)
            }
        }
        .background(BlueprintTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(BlueprintTheme.amber.opacity(0.4), lineWidth: 1)
        )
    }
}

private struct ExerciseTableSupersetBlockRow: View {
    let ex: Exercise

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(BlueprintTheme.mint)
                    .frame(width: 6, height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ex.name)
                        .font(.subheadline)
                        .foregroundStyle(BlueprintTheme.cream)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if ex.prescriptionIsAmrap || ex.prescriptionIsWarmup {
                        HStack(spacing: 6) {
                            if ex.prescriptionIsAmrap {
                                Text("AMRAP")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.mint)
                            }
                            if ex.prescriptionIsWarmup {
                                Text("Warm-up")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.mutedLight)
                            }
                        }
                    }
                    if let note = ex.trimmedProgramNotes {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            Text("\(ex.prescribedSets)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.mutedLight)
                .frame(width: 36, alignment: .trailing)

            Group {
                let plan = ex.maxWeight.trimmingCharacters(in: .whitespacesAndNewlines)
                if plan.isEmpty {
                    Text("—")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                } else {
                    Text(plan)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(plan.lowercased().contains("bodyweight") ? BlueprintTheme.muted : BlueprintTheme.lavender)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(planMaxChipBackground(ex.maxWeight))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .lineLimit(2)
            .multilineTextAlignment(.trailing)
            .layoutPriority(1)
            .fixedSize(horizontal: true, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private func planMaxChipBackground(_ raw: String) -> Color {
        let plan = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if plan.isEmpty || plan.lowercased().contains("bodyweight") {
            return Color.white.opacity(0.05)
        }
        return BlueprintTheme.purple.opacity(0.12)
    }
}
