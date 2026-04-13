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
    @State private var editorTemplate: LogWorkoutTemplate?
    @State private var showIncompleteSaveConfirm = false
    @State private var exerciseHistoryItem: ExerciseHistorySheetItem?
    @State private var showBlankWorkoutEditor = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let p = viewModel.activeProgram, let day = viewModel.activeDay {
                    Menu {
                        Button("Open detailed editor") {
                            editorTemplate = LogWorkoutTemplate(programName: p.name, dayLabel: day.label)
                        }
                        Button("New blank workout") {
                            showBlankWorkoutEditor = true
                        }
                        Button("Log from program…") {
                            editorTemplate = LogWorkoutTemplate(programName: nil, dayLabel: nil)
                        }
                        Button("Discard in-progress session", role: .destructive) {
                            viewModel.discardSession()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            finishSessionBar
        }
        .sheet(item: $editorTemplate) { tpl in
            NavigationStack {
                LogWorkoutEditorView(template: tpl)
            }
        }
        .sheet(isPresented: $showBlankWorkoutEditor) {
            NavigationStack {
                LogWorkoutEditorView(template: nil)
            }
        }
        .sheet(item: $exerciseHistoryItem) { item in
            NavigationStack {
                ExerciseHistoryView(exerciseName: item.name, loggedWorkouts: loggedWorkouts)
                    .environmentObject(appSettings)
            }
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

                    Picker("Active program", selection: Binding(
                        get: { viewModel.activeProgramId },
                        set: { viewModel.selectProgram(id: $0) }
                    )) {
                        ForEach(viewModel.programs) { program in
                            Text(programMenuLabel(program)).tag(program.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(BlueprintTheme.cream)
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

                    Picker("Training day", selection: Binding(
                        get: { viewModel.dayIndex },
                        set: { viewModel.setDayIndex($0) }
                    )) {
                        ForEach(Array(p.days.enumerated()), id: \.offset) { i, day in
                            Text(day.label).tag(i)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(BlueprintTheme.cream)
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

                            ForEach(viewModel.exerciseRows) { row in
                                QuickLogExerciseCard(row: row, viewModel: viewModel) {
                                    exerciseHistoryItem = ExerciseHistorySheetItem(name: row.name)
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

    /// Menu rows: name + subtitle when present so switching programs stays a deliberate, rare action.
    private func programMenuLabel(_ program: WorkoutProgram) -> String {
        program.subtitle.isEmpty ? program.name : "\(program.name) · \(program.subtitle)"
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

// MARK: - Quick log row

private struct QuickLogExerciseCard: View {
    let row: QuickExerciseState
    @ObservedObject var viewModel: WorkoutHubViewModel
    var onHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(BlueprintTheme.mint)
                    .frame(width: 6, height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.cream)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if let hint = row.prHint {
                            Text(hint)
                                .font(.caption2)
                                .foregroundStyle(BlueprintTheme.lavender.opacity(0.9))
                        }
                        Text("Plan: \(row.planDisplay)")
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.muted)
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
                nudgeChip(title: "Reps", value: "\(row.workingReps)", minus: { viewModel.nudgeReps(for: row.id, delta: -1) }, plus: { viewModel.nudgeReps(for: row.id, delta: 1) })
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
        .padding(12)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
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

            ForEach(day.exercises) { ex in
                HStack(alignment: .top, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle()
                            .fill(BlueprintTheme.mint)
                            .frame(width: 6, height: 6)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .padding(.top, 4)
                        Text(ex.name)
                            .font(.subheadline)
                            .foregroundStyle(BlueprintTheme.cream)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
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
                Divider().background(BlueprintTheme.border)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
