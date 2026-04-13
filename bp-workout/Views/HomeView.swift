import SwiftData
import SwiftUI

private let heroURL = URL(
    string: "https://d2xsxph8kpxj0f.cloudfront.net/310419663029914027/d4kuLRzxSXM9nrbbRPcbea/hero-banner-CmAYwVoABDY9NRPZkQCsYj.webp"
)!

/// Primary screen: pick program → day → log sets with PR-aware defaults (minimal typing).
struct WorkoutHubView: View {
    @StateObject private var viewModel = WorkoutHubViewModel()
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]
    @Environment(\.modelContext) private var modelContext

    @State private var showProgramTargets = false
    @State private var editorTemplate: LogWorkoutTemplate?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                compactHero
                let programs = viewModel.programs
                if !programs.isEmpty {
                    programSection(programs)
                    dayHeaderAndQuickLog
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .background(BlueprintTheme.bg)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let p = viewModel.activeProgram, let day = viewModel.activeDay {
                    Menu {
                        Button("Open detailed editor") {
                            editorTemplate = LogWorkoutTemplate(programName: p.name, dayLabel: day.label)
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
        .onAppear {
            viewModel.onAppear()
            viewModel.syncLoggedWorkouts(loggedWorkouts)
        }
        .onChange(of: loggedWorkouts.count) { _, _ in
            viewModel.syncLoggedWorkouts(loggedWorkouts)
        }
    }

    private var compactHero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: heroURL) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(BlueprintTheme.card)
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Rectangle().fill(BlueprintTheme.card)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [BlueprintTheme.bg.opacity(0.95), BlueprintTheme.bg.opacity(0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Pick a program and day, then tap Log set when the weight and reps match what you did.")
                    .font(.subheadline)
                    .foregroundStyle(BlueprintTheme.muted)
                if let stats = viewModel.stats {
                    Text("\(stats.totalPrograms) programs · \(stats.totalMonths) months of history · weights default from your last session or bundled PRs.")
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.muted.opacity(0.9))
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func programSection(_ programs: [WorkoutProgram]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Program")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BlueprintTheme.lavender)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(programs) { program in
                        ProgramChip(program: program, isSelected: program.id == viewModel.activeProgramId) {
                            viewModel.selectProgram(id: program.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var dayHeaderAndQuickLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = viewModel.activeProgram {
                HStack(alignment: .top, spacing: 8) {
                    Text(p.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.cream)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if p.isUserCreated == true {
                        Text("SELF-CREATED")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.mint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BlueprintTheme.mint.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Text("\(p.subtitle) · \(p.period)")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.muted)
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
                .padding(.horizontal, 20)

                if viewModel.dayIndex < p.days.count {
                    let day = p.days[viewModel.dayIndex]
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Today's session")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.lavender)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        ForEach(viewModel.exerciseRows) { row in
                            QuickLogExerciseCard(row: row, viewModel: viewModel)
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
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var finishSessionBar: some View {
        VStack(spacing: 8) {
            Button {
                viewModel.finishAndSave(modelContext: modelContext)
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
                        Text("Plan: \(row.templateMaxLabel)")
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.muted)
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                nudgeChip(title: "Wt", value: weightLabel, minus: { viewModel.nudgeWeight(for: row.id, delta: -2.5) }, plus: { viewModel.nudgeWeight(for: row.id, delta: 2.5) })
                nudgeChip(title: "Reps", value: "\(row.workingReps)", minus: { viewModel.nudgeReps(for: row.id, delta: -1) }, plus: { viewModel.nudgeReps(for: row.id, delta: 1) })
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.logSet(for: row.id)
                } label: {
                    Text("Log set")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(BlueprintTheme.purple)

                Button {
                    viewModel.repeatLastSet(for: row.id)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)
                .disabled(row.loggedSets.isEmpty)
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
                FlowSetChips(sets: row.loggedSets)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Logged")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(sets.enumerated()), id: \.offset) { _, s in
                    Text(chipLabel(s))
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

    private func chipLabel(_ s: LoggedSetSnapshot) -> String {
        if s.weight == 0 { return "BW×\(s.reps)" }
        return "\(WorkoutPrefill.formatWeight(s.weight))×\(s.reps)"
    }
}

// MARK: - Shared program UI

private struct ProgramChip: View {
    let program: WorkoutProgram
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(program.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? BlueprintTheme.cream : BlueprintTheme.mutedLight)
                    if program.isUserCreated == true {
                        Text("SELF")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BlueprintTheme.mint)
                    }
                }
                Text(program.subtitle)
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.muted)
                Text(program.period)
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.muted)
            }
            .padding(12)
            .frame(width: 200, alignment: .leading)
            .background(isSelected ? BlueprintTheme.purple.opacity(0.2) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? BlueprintTheme.purple : BlueprintTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
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

                    Text(ex.maxWeight)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isBodyweight(ex.maxWeight) ? BlueprintTheme.muted : BlueprintTheme.lavender)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isBodyweight(ex.maxWeight) ? Color.white.opacity(0.05) : BlueprintTheme.purple.opacity(0.12))
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
}
