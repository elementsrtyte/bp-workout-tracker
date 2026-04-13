import Combine
import SwiftUI

enum ProgramEditorRoute: Identifiable, Hashable {
    case create
    case editCustom(WorkoutProgram)
    case editBundled(WorkoutProgram)

    var id: String {
        switch self {
        case .create: return "__create__"
        case .editCustom(let p): return "c:\(p.id)"
        case .editBundled(let p): return "b:\(p.id)"
        }
    }
}

@MainActor
final class ProgramEditorViewModel: ObservableObject {
    enum Mode: Equatable {
        case create
        case editCustom
        case editBundled
    }

    let mode: Mode
    let stableId: String
    /// Preserved from the loaded program (or default for new); not user-editable in the UI.
    private let accentHexForSave: String

    @Published var name: String
    @Published var subtitle: String
    @Published var days: [EditableDay]

    struct EditableDay: Identifiable, Hashable {
        let id: UUID
        var label: String
        var exercises: [EditableExercise]
    }

    struct EditableExercise: Identifiable, Hashable {
        let id: UUID
        var name: String
        var maxWeight: String
        var targetSets: Int
    }

    init(route: ProgramEditorRoute) {
        switch route {
        case .create:
            mode = .create
            stableId = "user-\(UUID().uuidString)"
            accentHexForSave = WorkoutProgram.defaultAccentHex
            name = ""
            subtitle = ""
            days = [
                EditableDay(
                    id: UUID(),
                    label: "Day 1",
                    exercises: [
                        EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3),
                    ]
                ),
            ]
        case .editCustom(let p):
            mode = .editCustom
            stableId = p.id
            accentHexForSave = Self.normalizedAccentHex(p.color)
            name = p.name
            subtitle = p.subtitle
            days = Self.daysFromProgram(p)
        case .editBundled(let p):
            mode = .editBundled
            stableId = p.id
            accentHexForSave = Self.normalizedAccentHex(p.color)
            name = p.name
            subtitle = p.subtitle
            days = Self.daysFromProgram(p)
        }
    }

    private static func normalizedAccentHex(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return WorkoutProgram.defaultAccentHex }
        return t
    }

    private static func daysFromProgram(_ p: WorkoutProgram) -> [EditableDay] {
        let mapped = p.days.map { day in
            EditableDay(
                id: UUID(),
                label: day.label,
                exercises: day.exercises.map { ex in
                    EditableExercise(
                        id: UUID(),
                        name: ex.name,
                        maxWeight: ex.maxWeight,
                        targetSets: ex.targetSets ?? 3
                    )
                }
            )
        }
        if mapped.isEmpty {
            return [
                EditableDay(
                    id: UUID(),
                    label: "Day 1",
                    exercises: [EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3)],
                ),
            ]
        }
        return mapped
    }

    var canSave: Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return false }
        guard !days.isEmpty else { return false }
        for d in days {
            guard !d.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            let exOk = d.exercises.contains {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            guard exOk else { return false }
        }
        return true
    }

    func buildWorkoutProgram() -> WorkoutProgram {
        let workoutDays: [WorkoutDay] = days.map { d in
            let exs: [Exercise] = d.exercises.compactMap { ex in
                let n = ex.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !n.isEmpty else { return nil }
                let ts = max(1, min(20, ex.targetSets))
                return Exercise(name: n, maxWeight: ex.maxWeight.trimmingCharacters(in: .whitespacesAndNewlines), targetSets: ts)
            }
            return WorkoutDay(label: d.label.trimmingCharacters(in: .whitespacesAndNewlines), exercises: exs)
        }.filter { !$0.exercises.isEmpty }

        let isUser: Bool? = mode == .editBundled ? nil : true
        return WorkoutProgram(
            id: stableId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            period: "",
            dateRange: "",
            days: workoutDays,
            color: accentHexForSave,
            isUserCreated: isUser
        )
    }

    func addDay() {
        let n = days.count + 1
        var copy = days
        copy.append(
            EditableDay(
                id: UUID(),
                label: "Day \(n)",
                exercises: [EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3)],
            )
        )
        days = copy
    }

    func removeDay(at offsets: IndexSet) {
        var copy = days
        copy.remove(atOffsets: offsets)
        days = copy
        if days.isEmpty {
            addDay()
        }
    }

    func addExercise(dayIndex: Int) {
        guard days.indices.contains(dayIndex) else { return }
        var copy = days
        var d = copy[dayIndex]
        d.exercises.append(EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3))
        copy[dayIndex] = d
        days = copy
    }

    func removeExercises(dayIndex: Int, at offsets: IndexSet) {
        guard days.indices.contains(dayIndex) else { return }
        var copy = days
        var d = copy[dayIndex]
        d.exercises.remove(atOffsets: offsets)
        if d.exercises.isEmpty {
            d.exercises = [EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3)]
        }
        copy[dayIndex] = d
        days = copy
    }
}

private struct ProgramExerciseNameFieldID: Hashable {
    let dayIndex: Int
    let exIndex: Int
}

struct ProgramEditorView: View {
    let route: ProgramEditorRoute

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var programLibrary: UserProgramLibrary
    @ObservedObject private var bundle = BundleDataStore.shared
    @StateObject private var vm: ProgramEditorViewModel

    @State private var showRevertConfirm = false
    @State private var selectedDayIndex: Int = 0
    @FocusState private var focusedExerciseNameField: ProgramExerciseNameFieldID?

    init(route: ProgramEditorRoute) {
        self.route = route
        _vm = StateObject(wrappedValue: ProgramEditorViewModel(route: route))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                programDetailsCard

                VStack(alignment: .leading, spacing: 12) {
                    Text("Training days")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.cream.opacity(0.88))

                    dayPillStrip

                    if vm.days.indices.contains(selectedDayIndex) {
                        selectedDayEditorCard(dayIndex: selectedDayIndex)
                    }
                }

                Text("Each day needs a name and at least one exercise. Names are free-form; suggestions are optional.")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if case .editBundled(let p) = route, bundle.hasBundledOverride(programId: p.id) {
                    bundleRevertCard()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .padding(.bottom, 28)
        }
        .background(BlueprintTheme.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(BlueprintTheme.lavender)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!vm.canSave)
                    .foregroundStyle(vm.canSave ? BlueprintTheme.cream : BlueprintTheme.muted)
            }
        }
        .onChange(of: vm.days.count) { _, newCount in
            if selectedDayIndex >= newCount {
                selectedDayIndex = max(0, newCount - 1)
            }
        }
        .confirmationDialog(
            "Revert this program to the version from the app bundle?",
            isPresented: $showRevertConfirm,
            titleVisibility: .visible
        ) {
            Button("Revert", role: .destructive) {
                if case .editBundled(let p) = route {
                    bundle.removeBundledOverride(programId: p.id)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local edits will be removed.")
        }
        .tint(BlueprintTheme.purple)
    }

    private var programDetailsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Program")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            editorLabeledField(title: "Name", prompt: "e.g. Upper / Lower", text: $vm.name)
            editorLabeledField(title: "Subtitle (optional)", prompt: "Short description", text: $vm.subtitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dayPillStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(vm.days.enumerated()), id: \.element.id) { idx, day in
                    let selected = idx == selectedDayIndex
                    let label = day.label.trimmingCharacters(in: .whitespacesAndNewlines)
                    Button {
                        selectedDayIndex = idx
                    } label: {
                        Text(label.isEmpty ? "Day \(idx + 1)" : label)
                            .font(.subheadline.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? BlueprintTheme.cream : BlueprintTheme.mutedLight)
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                selected                                    ? BlueprintTheme.purple.opacity(0.38)
                                    : BlueprintTheme.cardInner
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        selected ? BlueprintTheme.lavender.opacity(0.55) : BlueprintTheme.border,
                                        lineWidth: 1
                                    )
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    vm.addDay()
                    selectedDayIndex = vm.days.count - 1
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.lavender)
                        .frame(width: 40, height: 40)
                        .background(BlueprintTheme.cardInner)
                        .overlay(
                            Circle()
                                .strokeBorder(BlueprintTheme.border, lineWidth: 1)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add training day")
            }
            .padding(.vertical, 2)
        }
    }

    private func selectedDayEditorCard(dayIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                editorLabeledField(title: "Day name", prompt: "e.g. Push, Pull, Legs", text: dayLabelBinding(dayIndex))
                    .frame(maxWidth: .infinity)

                if vm.days.count > 1 {
                    Button {
                        deleteDay(at: dayIndex)
                    } label: {
                        Image(systemName: "trash")
                            .font(.body.weight(.medium))
                            .foregroundStyle(BlueprintTheme.danger.opacity(0.9))
                            .frame(width: 44, height: 44)
                            .background(BlueprintTheme.cardInner)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(BlueprintTheme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove this day")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Exercises")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.muted)

                ForEach(Array(vm.days[dayIndex].exercises.enumerated()), id: \.element.id) { exIndex, _ in
                    exerciseEditorBlock(dayIndex: dayIndex, exIndex: exIndex)
                }

                Button {
                    vm.addExercise(dayIndex: dayIndex)
                } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.lavender)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func exerciseEditorBlock(dayIndex: Int, exIndex: Int) -> some View {
        let nameFieldID = ProgramExerciseNameFieldID(dayIndex: dayIndex, exIndex: exIndex)
        let canRemoveExercise = vm.days[dayIndex].exercises.count > 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text("Exercise \(exIndex + 1)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.muted)
                Spacer(minLength: 0)
                if canRemoveExercise {
                    Button {
                        vm.removeExercises(dayIndex: dayIndex, at: IndexSet(integer: exIndex))
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.danger.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove exercise")
                }
            }

            TextField("Exercise name", text: exerciseNameBinding(dayIndex: dayIndex, exIndex: exIndex))
                .textFieldStyle(.plain)
                .foregroundStyle(BlueprintTheme.cream)
                .focused($focusedExerciseNameField, equals: nameFieldID)
                .padding(12)
                .background(BlueprintTheme.cardInner)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BlueprintTheme.border, lineWidth: 1)
                )

            exerciseNameSuggestionList(dayIndex: dayIndex, exIndex: exIndex, fieldID: nameFieldID)

            HStack {
                Text("Working sets")
                    .font(.subheadline)
                    .foregroundStyle(BlueprintTheme.mutedLight)
                Spacer()
                Stepper(
                    value: exerciseTargetSetsBinding(dayIndex: dayIndex, exIndex: exIndex),
                    in: 1 ... 20
                ) {
                    Text("\(vm.days[dayIndex].exercises[exIndex].targetSets)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(BlueprintTheme.cream)
                        .frame(minWidth: 24, alignment: .trailing)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(12)
        .background(BlueprintTheme.cardInner.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BlueprintTheme.border.opacity(0.85), lineWidth: 1)
        )
    }

    private func bundleRevertCard() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bundle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            Button("Revert to bundle original", role: .destructive) {
                showRevertConfirm = true
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func deleteDay(at index: Int) {
        guard vm.days.count > 1 else { return }
        vm.removeDay(at: IndexSet(integer: index))
        selectedDayIndex = min(max(0, index - 1), max(0, vm.days.count - 1))
    }

    private func editorLabeledField(title: String, prompt: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(BlueprintTheme.cream)
                .padding(12)
                .background(BlueprintTheme.cardInner)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BlueprintTheme.border, lineWidth: 1)
                )
        }
    }

    private var title: String {
        switch route {
        case .create: return "New program"
        case .editCustom: return "Edit program"
        case .editBundled: return "Edit program (admin)"
        }
    }

    private func dayLabelBinding(_ dayIndex: Int) -> Binding<String> {
        Binding(
            get: { vm.days[dayIndex].label },
            set: { new in
                var copy = vm.days
                var d = copy[dayIndex]
                d.label = new
                copy[dayIndex] = d
                vm.days = copy
            }
        )
    }

    @ViewBuilder
    private func exerciseNameSuggestionList(dayIndex: Int, exIndex: Int, fieldID: ProgramExerciseNameFieldID) -> some View {
        if focusedExerciseNameField == fieldID {
            let query = vm.days[dayIndex].exercises[exIndex].name
            let suggestions = CommonExerciseNames.suggestions(matching: query, limit: 12)
            if !suggestions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                applyExerciseName(dayIndex: dayIndex, exIndex: exIndex, name: suggestion)
                                focusedExerciseNameField = nil
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .foregroundStyle(BlueprintTheme.cream)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 6)
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .background(BlueprintTheme.muted.opacity(0.35))
                        }
                    }
                }
                .frame(maxHeight: 176)
                .background(BlueprintTheme.bg.opacity(0.98))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BlueprintTheme.muted.opacity(0.45), lineWidth: 1)
                )
            }
        }
    }

    private func applyExerciseName(dayIndex: Int, exIndex: Int, name: String) {
        var copy = vm.days
        var d = copy[dayIndex]
        var e = d.exercises[exIndex]
        e.name = name
        d.exercises[exIndex] = e
        copy[dayIndex] = d
        vm.days = copy
    }

    private func exerciseNameBinding(dayIndex: Int, exIndex: Int) -> Binding<String> {
        Binding(
            get: { vm.days[dayIndex].exercises[exIndex].name },
            set: { new in
                var copy = vm.days
                var d = copy[dayIndex]
                var e = d.exercises[exIndex]
                e.name = new
                d.exercises[exIndex] = e
                copy[dayIndex] = d
                vm.days = copy
            }
        )
    }

    private func exerciseTargetSetsBinding(dayIndex: Int, exIndex: Int) -> Binding<Int> {
        Binding(
            get: { vm.days[dayIndex].exercises[exIndex].targetSets },
            set: { new in
                var copy = vm.days
                var d = copy[dayIndex]
                var e = d.exercises[exIndex]
                e.targetSets = new
                d.exercises[exIndex] = e
                copy[dayIndex] = d
                vm.days = copy
            }
        )
    }

    private func save() {
        let program = vm.buildWorkoutProgram()
        switch vm.mode {
        case .create, .editCustom:
            bundle.upsertCustomProgram(program)
        case .editBundled:
            bundle.setBundledOverride(program)
        }
        if case .create = route {
            programLibrary.setProgramInLibrary(program.id, enabled: true, catalog: bundle.mergedPrograms)
        }
        dismiss()
    }
}
