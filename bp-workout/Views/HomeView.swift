import SwiftData
import SwiftUI
import UIKit

private func dismissSoftwareKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

/// Primary screen: day-first logging; program changes rarely and stays in a compact picker.
struct WorkoutHubView: View {
    @StateObject private var viewModel = WorkoutHubViewModel()
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var programLibrary: UserProgramLibrary
    @ObservedObject private var bundleData = BundleDataStore.shared

    @State private var showIncompleteSaveConfirm = false
    @State private var showDiscardSessionConfirm = false
    @State private var exerciseHistoryItem: ExerciseHistorySheetItem?
    @State private var substitutionRoute: ExerciseSubstitutionSheetRoute?
    @State private var workoutSaveConfettiTrigger = 0

    private var catalogExerciseNames: [String] {
        bundleData.mergedPrograms.flatMap(\.days).flatMap(\.exercises).map(\.name)
    }

    var body: some View {
        ZStack {
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
            WorkoutSaveConfettiOverlay(trigger: workoutSaveConfettiTrigger)
                .allowsHitTesting(false)
        }
        .background(BlueprintTheme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(viewModel.activeDay?.label ?? "Workout")
                        .font(.headline)
                        .foregroundStyle(BlueprintTheme.cream)
                    if viewModel.hasLoggedSomething, let start = viewModel.sessionWallClockStart {
                        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                            Text(Self.formatSessionElapsed(since: start))
                                .font(.caption2.weight(.medium).monospacedDigit())
                                .foregroundStyle(BlueprintTheme.mint)
                        }
                    }
                }
            }
            if viewModel.canDiscardSession {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Cancel workout", role: .destructive) {
                            showDiscardSessionConfirm = true
                        }
                    } label: {
                        Text("•••")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .padding(.horizontal, 2)
                    }
                    .accessibilityLabel("Workout options")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    dismissSoftwareKeyboard()
                }
                .font(.body.weight(.semibold))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            restCountdownBar
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
            RestTimerNotificationScheduler.requestAuthorizationIfNeeded()
            viewModel.restBetweenSetsSeconds = appSettings.restBetweenSetsSeconds
            viewModel.onAppear()
            viewModel.syncLoggedWorkouts(loggedWorkouts)
        }
        .onChange(of: appSettings.restBetweenSetsSeconds) { _, v in
            viewModel.restBetweenSetsSeconds = v
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
                saveWorkoutAndCelebrateIfNeeded()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text(viewModel.incompleteSaveAlertMessage)
        }
        .confirmationDialog(
            "Cancel this workout?",
            isPresented: $showDiscardSessionConfirm,
            titleVisibility: .visible
        ) {
            Button("Discard session", role: .destructive) {
                viewModel.discardSession()
            }
            Button("Keep editing", role: .cancel) {}
        } message: {
            if viewModel.hasLoggedSomething {
                Text("Your logged sets will be removed from this session. Nothing is saved until you tap Save workout.")
            } else {
                Text("Any in-progress edits for this training day will be cleared.")
            }
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

                            finishSessionBar
                                .padding(.top, 8)
                                .padding(.bottom, 28)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private static func formatSessionElapsed(since start: Date) -> String {
        let t = max(0, Int(Date().timeIntervalSince(start)))
        let h = t / 3600
        let m = (t % 3600) / 60
        let s = t % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    @ViewBuilder
    private var restCountdownBar: some View {
        if let sec = viewModel.restSecondsRemaining, sec > 0 {
            HStack(spacing: 12) {
                Image(systemName: "timer")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest before next set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.cream)
                    Text("\(sec)s remaining · notification when time is up if the app is in the background")
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.cream.opacity(0.72))
                }
                Spacer(minLength: 0)
                Text("\(sec)s")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(BlueprintTheme.amber)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                Button("Skip") {
                    viewModel.skipRestTimer()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BlueprintTheme.lavender)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.regularMaterial)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(BlueprintTheme.cardInner.opacity(0.62))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                Color.white.opacity(0.06),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
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

    private func saveWorkoutAndCelebrateIfNeeded() {
        guard viewModel.finishAndSave(modelContext: modelContext) else { return }
        workoutSaveConfettiTrigger += 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var finishSessionBar: some View {
        VStack(spacing: 8) {
            Button {
                if viewModel.hasIncompletePlannedWork {
                    showIncompleteSaveConfirm = true
                } else {
                    saveWorkoutAndCelebrateIfNeeded()
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

private enum SetLogCelebrationKind: Equatable {
    case loggedSet
    case finishedExercise
}

private enum QuickLogCardChrome: Equatable {
    /// Normal card with border; optional lone “Superset” pill when `row.supersetGroup != nil`.
    case standalone
    /// Row inside `SupersetQuickLogBlock` (shared chrome; no per-row border).
    case supersetGroupedRow
}

/// Non-layout celebration: glowing, pulsating stroke + sparkles on the card (no extra vertical space).
private struct QuickLogCelebrationGlowOverlay: View {
    let kind: SetLogCelebrationKind
    var pulse: CGFloat
    var burst: CGFloat
    var chrome: QuickLogCardChrome

    private var cornerRadius: CGFloat { chrome == .standalone ? 10 : 8 }

    private var accent: Color {
        kind == .finishedExercise ? BlueprintTheme.amber : BlueprintTheme.mint
    }

    private var secondary: Color {
        kind == .finishedExercise ? BlueprintTheme.cream : BlueprintTheme.lavender
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 45.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breathe = 0.5 + 0.5 * sin(t * 6.8)
            let twinkle = 0.5 + 0.5 * sin(t * 10.5)
            let lineW = 1.5 + (pulse - 1) * 5 + CGFloat(breathe) * 2.4
            let haloOpacity = 0.22 + 0.18 * CGFloat(breathe) + 0.12 * burst
            let glowR = 9 + (pulse - 1) * 15 + burst * 11 + CGFloat(breathe) * 9
            let spin = t * 1.15
            let gx = 0.5 + 0.42 * cos(spin)
            let gy = 0.5 + 0.42 * sin(spin)

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(accent.opacity(haloOpacity), lineWidth: 5 + 4 * CGFloat(breathe))
                    .blur(radius: 2.5 + 1.5 * CGFloat(breathe))
                    .padding(chrome == .standalone ? 2 : 1)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.62),
                                accent.opacity(0.98),
                                secondary.opacity(0.72),
                                accent.opacity(0.82),
                                Color.white.opacity(0.38),
                            ],
                            startPoint: UnitPoint(x: gx, y: gy),
                            endPoint: UnitPoint(x: 1 - gx, y: 1 - gy)
                        ),
                        lineWidth: lineW
                    )
                    .shadow(
                        color: accent.opacity(0.5 + 0.22 * burst + 0.12 * CGFloat(breathe)),
                        radius: glowR * 0.55
                    )
                    .shadow(color: accent.opacity(0.26), radius: glowR)
                    .shadow(
                        color: Color.white.opacity(0.07 + 0.07 * CGFloat(twinkle)),
                        radius: 5 + 3 * CGFloat(twinkle)
                    )
                    .padding(chrome == .standalone ? 2 : 1)

                GeometryReader { geo in
                    let cx = geo.size.width * 0.5
                    let cy = geo.size.height * 0.5
                    let rx = max(geo.size.width * 0.48, 24)
                    let ry = max(geo.size.height * 0.48, 24)
                    let sparkleCount = kind == .finishedExercise ? 10 : 7
                    ForEach(0..<sparkleCount, id: \.self) { i in
                        let base = Double(i) / Double(sparkleCount) * 2 * Double.pi
                        let wobble = sin(t * 5.2 + Double(i) * 0.85)
                        let angle = base + t * 0.55 + 0.12 * wobble
                        let radial = 1.02 + 0.04 * sin(t * 4 + Double(i))
                        let ox = CGFloat(cos(angle)) * rx * CGFloat(radial)
                        let oy = CGFloat(sin(angle)) * ry * CGFloat(radial)
                        let flicker = 0.28 + 0.62 * pow(0.5 + 0.5 * sin(t * 8.5 + Double(i) * 1.1), 2)
                        Image(systemName: "sparkle")
                            .font(.system(size: i % 3 == 0 ? 8 : 6, weight: .bold))
                            .foregroundStyle(
                                i % 2 == 0
                                    ? accent.opacity(0.85)
                                    : secondary.opacity(0.9)
                            )
                            .opacity(flicker)
                            .scaleEffect(0.65 + 0.35 * CGFloat(twinkle) + (i % 4 == 0 ? 0.08 : 0))
                            .position(x: cx + ox, y: cy + oy)
                    }
                }
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(1 + 0.01 * CGFloat(breathe))
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

private struct LoggedSetEditRoute: Identifiable {
    let id = UUID()
    let setIndex: Int
    let snapshot: LoggedSetSnapshot
}

private struct EditLoggedSetSheet: View {
    let exerciseName: String
    let setNumber: Int
    let initial: LoggedSetSnapshot
    let onSave: (Double, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weightText: String
    @State private var reps: Int

    init(exerciseName: String, setNumber: Int, initial: LoggedSetSnapshot, onSave: @escaping (Double, Int) -> Void) {
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.initial = initial
        self.onSave = onSave
        _weightText = State(
            initialValue: initial.weight == 0 ? "BW" : WorkoutPrefill.formatWeight(initial.weight)
        )
        _reps = State(initialValue: initial.reps)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(exerciseName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.cream)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weight")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                    TextField("lb or BW", text: $weightText)
                        .keyboardType(.decimalPad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(BlueprintTheme.cream)
                        .padding(12)
                        .background(BlueprintTheme.cardInner)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(BlueprintTheme.border, lineWidth: 1)
                        )
                }
                HStack(spacing: 12) {
                    Text("Reps")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                    Spacer(minLength: 0)
                    Button {
                        reps = max(1, reps - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption.weight(.bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.bordered)
                    Text("\(reps)")
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(BlueprintTheme.cream)
                        .frame(minWidth: 36)
                    Button {
                        reps = min(999, reps + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption.weight(.bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.bordered)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BlueprintTheme.bg)
            .navigationTitle("Edit set \(setNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissSoftwareKeyboard()
                    }
                    .font(.body.weight(.semibold))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let w = Self.parseWeight(weightText, fallback: initial.weight)
                        onSave(w, reps)
                        dismiss()
                    }
                    .disabled(reps < 1)
                }
            }
            .tint(BlueprintTheme.purple)
        }
    }

    private static func parseWeight(_ raw: String, fallback: Double) -> Double {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return fallback }
        let lower = t.lowercased()
        if lower == "bw" || lower == "bodyweight" { return 0 }
        let norm = t.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(norm) else { return fallback }
        return max(0, (v * 4).rounded() / 4)
    }
}

private struct QuickLogExerciseCard: View {
    let row: QuickExerciseState
    @ObservedObject var viewModel: WorkoutHubViewModel
    var chrome: QuickLogCardChrome = .standalone
    var onHistory: () -> Void
    var onSwapExercise: () -> Void

    @State private var weightEntry: String = ""
    @FocusState private var weightFieldFocused: Bool
    @State private var celebration: SetLogCelebrationKind?
    @State private var celebrationPulse: CGFloat = 1
    @State private var celebrationBurst: CGFloat = 0
    @State private var sensorySetTick = 0
    @State private var sensoryExerciseTick = 0
    @State private var loggedSetEditRoute: LoggedSetEditRoute?

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
                    if let t = row.prescribedTargetReps, !row.isAmrap {
                        Text("Target: \(t) reps / set")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.lavender)
                    }
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
                weightInputColumn
                nudgeChip(
                    title: row.isAmrap ? "Reps (AMRAP)" : "Reps",
                    value: "\(row.workingReps)",
                    minus: { viewModel.nudgeReps(for: row.id, delta: -1) },
                    plus: { viewModel.nudgeReps(for: row.id, delta: 1) }
                )
            }
            .onAppear { syncWeightEntry() }
            .onChange(of: row.workingWeight) { _, _ in
                if !weightFieldFocused { syncWeightEntry() }
            }

            HStack(spacing: 8) {
                Button {
                    commitWeightEntry()
                    let outcome = viewModel.logSet(for: row.id)
                    switch outcome {
                    case .loggedSetContinuing:
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        sensorySetTick += 1
                        celebrationBurst = 0
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) {
                            celebration = .loggedSet
                            celebrationPulse = 1.06
                        }
                        withAnimation(.easeOut(duration: 0.78)) {
                            celebrationBurst = 1
                        }
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.08)) {
                            celebrationPulse = 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation(.easeOut(duration: 0.22)) {
                                celebration = nil
                                celebrationBurst = 0
                            }
                        }
                    case .finishedExercise:
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        sensoryExerciseTick += 1
                        celebrationBurst = 0
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                            celebration = .finishedExercise
                            celebrationPulse = 1.1
                        }
                        withAnimation(.easeOut(duration: 1.02)) {
                            celebrationBurst = 1
                        }
                        withAnimation(.spring(response: 0.58, dampingFraction: 0.78).delay(0.12)) {
                            celebrationPulse = 1
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                            withAnimation(.easeOut(duration: 0.28)) {
                                celebration = nil
                                celebrationBurst = 0
                            }
                        }
                    case .noop:
                        break
                    }
                } label: {
                    Text(row.isSetsComplete ? "All sets logged" : "Log set \(row.loggedSets.count + 1) of \(row.targetSets)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(row.isSetsComplete ? BlueprintTheme.mint : BlueprintTheme.purple)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: row.isSetsComplete)
                .animation(.spring(response: 0.35, dampingFraction: 0.78), value: row.loggedSets.count)
                .disabled(row.isSetsComplete)
                .sensoryFeedback(.increase, trigger: sensorySetTick)
                .sensoryFeedback(.success, trigger: sensoryExerciseTick)

                Menu {
                    Button("Swap exercise…") {
                        onSwapExercise()
                    }
                    Button("Repeat last set") {
                        commitWeightEntry()
                        viewModel.repeatLastSet(for: row.id)
                    }
                    .disabled(row.loggedSets.isEmpty || row.isSetsComplete)
                    Button("Undo last set", role: .destructive) {
                        viewModel.removeLastSet(for: row.id)
                    }
                    .disabled(row.loggedSets.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("More options")
            }

            if !row.loggedSets.isEmpty {
                FlowSetChips(sets: row.loggedSets, targetSets: row.targetSets) { index, snapshot in
                    loggedSetEditRoute = LoggedSetEditRoute(setIndex: index, snapshot: snapshot)
                }
            }
        }

        chromeBody(inner)
            .overlay {
                if let c = celebration {
                    QuickLogCelebrationGlowOverlay(
                        kind: c,
                        pulse: celebrationPulse,
                        burst: celebrationBurst,
                        chrome: chrome
                    )
                }
            }
            .sheet(item: $loggedSetEditRoute) { route in
                EditLoggedSetSheet(
                    exerciseName: row.name,
                    setNumber: route.setIndex + 1,
                    initial: route.snapshot,
                    onSave: { w, r in
                        viewModel.replaceLoggedSet(for: row.id, setIndex: route.setIndex, weight: w, reps: r)
                    }
                )
            }
    }

    @ViewBuilder
    private func chromeBody(_ inner: some View) -> some View {
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

    private func syncWeightEntry() {
        if row.workingWeight == 0 { weightEntry = "BW" }
        else { weightEntry = WorkoutPrefill.formatWeight(row.workingWeight) }
    }

    private func commitWeightEntry() {
        viewModel.setWorkingWeightFromString(for: row.id, raw: weightEntry)
        syncWeightEntry()
    }

    private var weightInputColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            HStack(spacing: 4) {
                Button {
                    viewModel.nudgeWeight(for: row.id, delta: -2.5)
                } label: {
                    Image(systemName: "minus")
                        .font(.caption.weight(.bold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
                TextField("lb", text: $weightEntry)
                    .focused($weightFieldFocused)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(BlueprintTheme.cream)
                    .frame(minWidth: 56)
                    .onSubmit { commitWeightEntry() }
                Button {
                    viewModel.nudgeWeight(for: row.id, delta: 2.5)
                } label: {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: weightFieldFocused) { _, on in
            if !on { commitWeightEntry() }
        }
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
    var onEditSet: (Int, LoggedSetSnapshot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Logged · tap to edit")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(sets.enumerated()), id: \.offset) { i, s in
                    Button {
                        onEditSet(i, s)
                    } label: {
                        Text(chipLabel(setIndex: i + 1, s))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(BlueprintTheme.cream)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(BlueprintTheme.purple.opacity(0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit set \(i + 1), \(chipLabel(setIndex: i + 1, s))")
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

// MARK: - Workout saved confetti

private struct ConfettiRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xD1CE_F00D : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private struct ConfettiShard: Identifiable {
    let id: Int
    let xNorm: CGFloat
    let delay: CGFloat
    let fallSpeed: CGFloat
    let wobble: CGFloat
    let startBoost: CGFloat
    let w: CGFloat
    let h: CGFloat
    let corner: CGFloat
    let color: Color
    let angle0: Double
    let angle1: Double

    static func make(count: Int, seed: UInt64) -> [ConfettiShard] {
        var rng = ConfettiRNG(seed: seed)
        let palette: [Color] = [
            BlueprintTheme.mint,
            BlueprintTheme.amber,
            BlueprintTheme.lavender,
            BlueprintTheme.cream,
            BlueprintTheme.purple,
        ]
        return (0..<count).map { i in
            let color = palette[Int.random(in: palette.indices, using: &rng)]
            return ConfettiShard(
                id: i,
                xNorm: .random(in: 0.02...0.98, using: &rng),
                delay: .random(in: 0...0.42, using: &rng),
                fallSpeed: .random(in: 0.82...1.12, using: &rng),
                wobble: .random(in: 0...(CGFloat.pi * 2), using: &rng),
                startBoost: .random(in: 0...120, using: &rng),
                w: .random(in: 5...10, using: &rng),
                h: .random(in: 9...19, using: &rng),
                corner: .random(in: 1.2...3.2, using: &rng),
                color: color,
                angle0: .random(in: -35...35, using: &rng),
                angle1: .random(in: 220...540, using: &rng)
            )
        }
    }
}

private struct WorkoutSaveConfettiOverlay: View {
    let trigger: Int
    @State private var progress: CGFloat = 0
    @State private var shards: [ConfettiShard] = []

    var body: some View {
        GeometryReader { geo in
            let fade = shardOpacity(progress: progress)
            ZStack {
                ForEach(shards) { s in
                    RoundedRectangle(cornerRadius: s.corner, style: .continuous)
                        .fill(s.color)
                        .frame(width: s.w, height: s.h)
                        .rotationEffect(.degrees(s.angle0 + (s.angle1 - s.angle0) * Double(progress)))
                        .position(position(for: s, in: geo, progress: progress))
                        .opacity(fade)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .onChange(of: trigger) { _, newValue in
            guard newValue > 0 else { return }
            shards = ConfettiShard.make(count: 68, seed: UInt64(truncatingIfNeeded: newValue))
            progress = 0
            withAnimation(.timingCurve(0.12, 0.88, 0.0, 1.0, duration: 2.7)) {
                progress = 1
            }
        }
    }

    private func position(for s: ConfettiShard, in geo: GeometryProxy, progress: CGFloat) -> CGPoint {
        let w = geo.size.width
        let h = geo.size.height
        let denom = max(0.05, 1 - s.delay)
        let rawT = (progress - s.delay) / denom
        let t = max(0, min(1, rawT))
        let eased = 1 - pow(1 - t, 2.2)
        let x = s.xNorm * w + sin(eased * .pi * 2.05 + s.wobble) * 48 * eased
        let y0: CGFloat = -24 - s.startBoost
        let y = y0 + (h + s.startBoost + 90) * eased * s.fallSpeed
        return CGPoint(x: x, y: y)
    }

    private func shardOpacity(progress: CGFloat) -> CGFloat {
        if progress < 0.76 { return 1 }
        let u = (progress - 0.76) / 0.24
        return max(0, 1 - u)
    }
}
