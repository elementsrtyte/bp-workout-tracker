import Combine
import SwiftUI

enum ProgramEditorRoute: Identifiable, Hashable {
    case create
    /// Parsed from pasted text (LLM); new stable id already assigned on the program.
    case createFromImport(WorkoutProgram)
    case editCustom(WorkoutProgram)
    case editBundled(WorkoutProgram)

    var id: String {
        switch self {
        case .create: return "__create__"
        case .createFromImport(let p): return "i:\(p.id)"
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
    /// Shown only for bundled programs; kept when saving so catalog metadata is not wiped.
    private let catalogPeriod: String
    private let catalogDateRange: String

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
        /// Reps per working set (ignored when AMRAP is on).
        var targetReps: Int
        /// Same number groups exercises into a superset; nil = not in a superset.
        var supersetGroup: Int?
        var isAmrap: Bool
        var isWarmup: Bool
        var notes: String
    }

    init(route: ProgramEditorRoute) {
        switch route {
        case .create:
            mode = .create
            stableId = "user-\(UUID().uuidString)"
            accentHexForSave = WorkoutProgram.defaultAccentHex
            catalogPeriod = ""
            catalogDateRange = ""
            name = ""
            subtitle = ""
            days = [
                EditableDay(
                    id: UUID(),
                    label: "Day 1",
                    exercises: [
                        EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3, targetReps: 8, supersetGroup: nil, isAmrap: false, isWarmup: false, notes: ""),
                    ]
                ),
            ]
        case .createFromImport(let p):
            mode = .create
            stableId = p.id
            accentHexForSave = Self.normalizedAccentHex(p.color)
            catalogPeriod = ""
            catalogDateRange = ""
            name = p.name
            subtitle = p.subtitle
            days = Self.daysFromProgram(p)
        case .editCustom(let p):
            mode = .editCustom
            stableId = p.id
            accentHexForSave = Self.normalizedAccentHex(p.color)
            catalogPeriod = ""
            catalogDateRange = ""
            name = p.name
            subtitle = p.subtitle
            days = Self.daysFromProgram(p)
        case .editBundled(let p):
            mode = .editBundled
            stableId = p.id
            accentHexForSave = Self.normalizedAccentHex(p.color)
            catalogPeriod = p.period
            catalogDateRange = p.dateRange
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
                        targetSets: ex.targetSets ?? 3,
                        targetReps: ex.prescribedRepTarget ?? 8,
                        supersetGroup: ex.supersetGroup,
                        isAmrap: ex.prescriptionIsAmrap,
                        isWarmup: ex.prescriptionIsWarmup,
                        notes: ex.notes ?? ""
                    )
                }
            )
        }
        if mapped.isEmpty {
            return [
                EditableDay(
                    id: UUID(),
                    label: "Day 1",
                    exercises: [EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3, targetReps: 8, supersetGroup: nil, isAmrap: false, isWarmup: false, notes: "")],
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
                let sg = ex.supersetGroup.flatMap { (1 ... 6).contains($0) ? $0 : nil }
                let repT: Int? = ex.isAmrap ? nil : max(1, min(100, ex.targetReps))
                return Exercise(
                    name: n,
                    maxWeight: ex.maxWeight.trimmingCharacters(in: .whitespacesAndNewlines),
                    targetSets: ts,
                    targetReps: repT,
                    supersetGroup: sg,
                    isAmrap: ex.isAmrap ? true : nil,
                    isWarmup: ex.isWarmup ? true : nil,
                    notes: {
                        let t = ex.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                        return t.isEmpty ? nil : t
                    }()
                )
            }
            return WorkoutDay(label: d.label.trimmingCharacters(in: .whitespacesAndNewlines), exercises: exs)
        }.filter { !$0.exercises.isEmpty }

        let isUser: Bool? = mode == .editBundled ? nil : true
        let period = mode == .editBundled ? catalogPeriod : ""
        let dateRange = mode == .editBundled ? catalogDateRange : ""
        return WorkoutProgram(
            id: stableId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            period: period,
            dateRange: dateRange,
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
                exercises: [EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3, targetReps: 8, supersetGroup: nil, isAmrap: false, isWarmup: false, notes: "")],
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
        d.exercises.append(EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3, targetReps: 8, supersetGroup: nil, isAmrap: false, isWarmup: false, notes: ""))
        copy[dayIndex] = d
        days = copy
    }

    func removeExercises(dayIndex: Int, at offsets: IndexSet) {
        guard days.indices.contains(dayIndex) else { return }
        var copy = days
        var d = copy[dayIndex]
        d.exercises.remove(atOffsets: offsets)
        if d.exercises.isEmpty {
            d.exercises = [EditableExercise(id: UUID(), name: "", maxWeight: "", targetSets: 3, targetReps: 8, supersetGroup: nil, isAmrap: false, isWarmup: false, notes: "")]
        }
        copy[dayIndex] = d
        days = copy
    }
}

private struct ProgramExerciseNameFieldID: Hashable {
    let dayIndex: Int
    let exIndex: Int
}

/// Horizontal chips (None + 1…6) instead of a menu picker — matches day pills / SS accent.
private struct ProgramSupersetGroupSelector: View {
    @Binding var selection: Int?

    private static let groups = Array(1 ... 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Superset")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            Text("Same number means back-to-back in one round. Leave as None for a standalone lift.")
                .font(.caption2)
                .foregroundStyle(BlueprintTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(label: "None", value: nil)
                    ForEach(Self.groups, id: \.self) { g in
                        chip(label: "\(g)", value: g)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(label: String, value: Int?) -> some View {
        let selected = selection == value
        let isGroup = value != nil
        return Button {
            selection = value
        } label: {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(foreground(for: selected, isGroup: isGroup))
                .padding(.horizontal, isGroup ? 13 : 14)
                .padding(.vertical, 9)
                .background(background(for: selected, isGroup: isGroup))
                .overlay(
                    Capsule()
                        .strokeBorder(stroke(for: selected, isGroup: isGroup), lineWidth: 1)
                )
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(value: value))
    }

    private func foreground(for selected: Bool, isGroup: Bool) -> Color {
        if selected {
            return isGroup ? BlueprintTheme.amber : BlueprintTheme.cream
        }
        return BlueprintTheme.mutedLight
    }

    private func background(for selected: Bool, isGroup: Bool) -> Color {
        if selected {
            return isGroup ? BlueprintTheme.amber.opacity(0.24) : BlueprintTheme.purple.opacity(0.32)
        }
        return BlueprintTheme.bg.opacity(0.55)
    }

    private func stroke(for selected: Bool, isGroup: Bool) -> Color {
        if selected {
            return isGroup ? BlueprintTheme.amber.opacity(0.65) : BlueprintTheme.lavender.opacity(0.55)
        }
        return BlueprintTheme.border
    }

    private func accessibilityLabel(value: Int?) -> String {
        if let value {
            return "Superset group \(value)"
        }
        return "Not in a superset"
    }
}

/// Collapsed by default; supersets, AMRAP, and warm-up prescriptions.
private struct ProgramExerciseAdvancedOptionsSection: View {
    let summarySubtitle: String?
    @Binding var supersetGroup: Int?
    @Binding var isAmrap: Bool
    @Binding var isWarmup: Bool
    @Binding var notes: String
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Notes")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                    TextField("Cues, equipment, intent…", text: $notes, axis: .vertical)
                        .textFieldStyle(.plain)
                        .foregroundStyle(BlueprintTheme.cream)
                        .lineLimit(3 ... 8)
                        .padding(12)
                        .background(BlueprintTheme.bg.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(BlueprintTheme.border, lineWidth: 1)
                        )
                }

                ProgramSupersetGroupSelector(selection: $supersetGroup)

                Toggle(isOn: $isAmrap) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AMRAP")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.cream)
                        Text("Reps to failure each set (log what you get).")
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.muted)
                    }
                }
                .tint(BlueprintTheme.lavender)

                Toggle(isOn: $isWarmup) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Warm-up / activation")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.cream)
                        Text("Skipping these won’t block saving the session.")
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.muted)
                    }
                }
                .tint(BlueprintTheme.lavender)
            }
            .padding(.top, 4)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                    Text("Advanced options")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.mutedLight)
                }
                if let summarySubtitle, !summarySubtitle.isEmpty {
                    Text(summarySubtitle)
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.muted)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(BlueprintTheme.lavender)
    }
}

struct ProgramEditorView: View {
    let route: ProgramEditorRoute

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var programLibrary: UserProgramLibrary
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var auth: SupabaseSessionManager = .shared
    @ObservedObject private var bundle = BundleDataStore.shared
    @StateObject private var vm: ProgramEditorViewModel

    @State private var showRevertConfirm = false
    @State private var isPublishingCatalog = false
    @State private var publishCatalogError: String?
    @State private var selectedDayIndex: Int = 0
    @FocusState private var focusedExerciseNameField: ProgramExerciseNameFieldID?
    @State private var aiRelatedByField: [ProgramExerciseNameFieldID: [String]] = [:]
    @State private var aiRelatedLoading: ProgramExerciseNameFieldID?
    @State private var aiRelatedError: String?

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
                            .id("\(selectedDayIndex)|\(programEditorDayIdsFingerprint)")
                    }
                }

                Text("Each day needs a name and at least one exercise. Supersets, AMRAP, warm-up, and optional notes are under Advanced options on each exercise.")
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
        .blueprintDismissKeyboardOnScroll()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(BlueprintTheme.lavender)
            }
            ToolbarItem(placement: .confirmationAction) {
                let saveEnabled = vm.canSave && !isPublishingCatalog
                Button("Save") { save() }
                    .disabled(!saveEnabled)
                    .fontWeight(.semibold)
                    .foregroundStyle(saveEnabled ? BlueprintTheme.cream : BlueprintTheme.muted.opacity(0.38))
            }
        }
        .onChange(of: vm.days.count) { _, _ in
            reconcileProgramEditorDaySelection()
        }
        .onChange(of: programEditorDayIdsFingerprint) { _, _ in
            reconcileProgramEditorDaySelection()
        }
        .onChange(of: focusedExerciseNameField) { _, _ in
            aiRelatedError = nil
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
        .alert("Could not publish catalog", isPresented: Binding(
            get: { publishCatalogError != nil },
            set: { if !$0 { publishCatalogError = nil } }
        )) {
            Button("OK", role: .cancel) { publishCatalogError = nil }
        } message: {
            Text(publishCatalogError ?? "")
        }
        .tint(BlueprintTheme.purple)
    }

    /// Stable fingerprint when days are added/removed/reordered (ids change).
    private var programEditorDayIdsFingerprint: String {
        vm.days.map(\.id.uuidString).joined(separator: ",")
    }

    /// Keeps selection valid after `vm.days` mutations; clears focus so stale TextField bindings cannot outlive the row.
    private func reconcileProgramEditorDaySelection() {
        guard !vm.days.isEmpty else { return }
        if !vm.days.indices.contains(selectedDayIndex) {
            selectedDayIndex = min(max(0, selectedDayIndex), vm.days.count - 1)
            focusedExerciseNameField = nil
        }
    }

    private func exerciseIndicesAreValid(dayIndex: Int, exIndex: Int) -> Bool {
        guard vm.days.indices.contains(dayIndex) else { return false }
        return vm.days[dayIndex].exercises.indices.contains(exIndex)
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

    private func exerciseAdvancedOptionsSummary(_ ex: ProgramEditorViewModel.EditableExercise) -> String? {
        var parts: [String] = []
        if let g = ex.supersetGroup {
            parts.append("Superset \(g)")
        }
        if !ex.isAmrap { parts.append("\(ex.targetReps) reps") }
        if ex.isAmrap { parts.append("AMRAP") }
        if ex.isWarmup { parts.append("Warm-up") }
        if !ex.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Notes")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private func exerciseEditorBlock(dayIndex: Int, exIndex: Int) -> some View {
        Group {
            if exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) {
                exerciseEditorBlockContent(dayIndex: dayIndex, exIndex: exIndex)
            }
        }
    }

    private func exerciseEditorBlockContent(dayIndex: Int, exIndex: Int) -> some View {
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
                .tint(BlueprintTheme.lavender)
            }
            .padding(.horizontal, 4)

            HStack {
                Text("Reps / set")
                    .font(.subheadline)
                    .foregroundStyle(BlueprintTheme.mutedLight)
                Spacer()
                Stepper(
                    value: exerciseTargetRepsBinding(dayIndex: dayIndex, exIndex: exIndex),
                    in: 1 ... 30
                ) {
                    Text("\(vm.days[dayIndex].exercises[exIndex].targetReps)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(BlueprintTheme.cream)
                        .frame(minWidth: 24, alignment: .trailing)
                }
                .tint(BlueprintTheme.lavender)
                .disabled(vm.days[dayIndex].exercises[exIndex].isAmrap)
            }
            .padding(.horizontal, 4)
            if vm.days[dayIndex].exercises[exIndex].isAmrap {
                Text("Rep target is hidden for AMRAP (reps to failure).")
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.muted)
            }

            ProgramExerciseAdvancedOptionsSection(
                summarySubtitle: exerciseAdvancedOptionsSummary(vm.days[dayIndex].exercises[exIndex]),
                supersetGroup: exerciseSupersetGroupBinding(dayIndex: dayIndex, exIndex: exIndex),
                isAmrap: exerciseAmrapBinding(dayIndex: dayIndex, exIndex: exIndex),
                isWarmup: exerciseWarmupBinding(dayIndex: dayIndex, exIndex: exIndex),
                notes: exerciseNotesBinding(dayIndex: dayIndex, exIndex: exIndex)
            )
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
        let removed = index
        let countAfter = vm.days.count - 1
        var newSelected = selectedDayIndex
        if newSelected > removed {
            newSelected -= 1
        } else if newSelected == removed {
            newSelected = min(max(0, removed - 1), max(0, countAfter - 1))
        }
        newSelected = min(max(0, newSelected), max(0, countAfter - 1))
        focusedExerciseNameField = nil
        selectedDayIndex = newSelected
        vm.removeDay(at: IndexSet(integer: index))
        selectedDayIndex = min(max(0, selectedDayIndex), max(0, vm.days.count - 1))
        reconcileProgramEditorDaySelection()
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
        case .createFromImport: return "Imported program"
        case .editCustom: return "Edit program"
        case .editBundled: return "Edit program"
        }
    }

    private func dayLabelBinding(_ dayIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard vm.days.indices.contains(dayIndex) else { return "" }
                return vm.days[dayIndex].label
            },
            set: { new in
                guard vm.days.indices.contains(dayIndex) else { return }
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
        if focusedExerciseNameField == fieldID, exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) {
            let query = vm.days[dayIndex].exercises[exIndex].name
            let suggestions = CommonExerciseNames.suggestions(matching: query, limit: 12)
            let aiReady = BlueprintAPIConfig.isConfigured && auth.phase == .signedIn
            let aiPicks = aiRelatedByField[fieldID] ?? []
            if !suggestions.isEmpty || aiReady {
                VStack(alignment: .leading, spacing: 10) {
                    if !suggestions.isEmpty {
                        Text("Catalog matches")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.muted)
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
                    }

                    if aiReady {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI — catalog only")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BlueprintTheme.muted)
                            Text("Suggestions are restricted to names in the static catalog list.")
                                .font(.caption2)
                                .foregroundStyle(BlueprintTheme.mutedLight)
                            Button {
                                Task {
                                    await loadAIRelatedCatalogPicks(
                                        dayIndex: dayIndex,
                                        exIndex: exIndex,
                                        fieldID: fieldID
                                    )
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    if aiRelatedLoading == fieldID {
                                        ProgressView()
                                            .tint(BlueprintTheme.lavender)
                                    }
                                    Text(aiRelatedLoading == fieldID ? "Loading…" : "Suggest related exercises")
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(BlueprintTheme.lavender)
                            .disabled(aiRelatedLoading == fieldID)

                            if let aiRelatedError, focusedExerciseNameField == fieldID {
                                Text(aiRelatedError)
                                    .font(.caption2)
                                    .foregroundStyle(BlueprintTheme.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if !aiPicks.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(aiPicks, id: \.self) { pick in
                                            Button {
                                                applyExerciseName(dayIndex: dayIndex, exIndex: exIndex, name: pick)
                                                focusedExerciseNameField = nil
                                            } label: {
                                                Text(pick)
                                                    .font(.caption.weight(.medium))
                                                    .foregroundStyle(BlueprintTheme.cream)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 8)
                                                    .background(BlueprintTheme.purple.opacity(0.28))
                                                    .clipShape(Capsule())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(BlueprintTheme.bg.opacity(0.98))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BlueprintTheme.muted.opacity(0.45), lineWidth: 1)
                )
            }
        }
    }

    private func loadAIRelatedCatalogPicks(
        dayIndex: Int,
        exIndex: Int,
        fieldID: ProgramExerciseNameFieldID
    ) async {
               guard BlueprintAPIConfig.isConfigured, auth.phase == .signedIn else {
            aiRelatedError = "Sign in and configure the Blueprint API to use AI suggestions."
            return
        }
        guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return }
        let name = vm.days[dayIndex].exercises[exIndex].name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            aiRelatedError = "Type an exercise name (or partial) for context, then try again."
            return
        }
        aiRelatedError = nil
        aiRelatedLoading = fieldID
        defer { aiRelatedLoading = nil }
        do {
            let picks = try await OpenAIRelatedCatalogExerciseClient.fetchRelated(
                exerciseName: name,
                allowedExactNames: CommonExerciseNames.all,
                limit: 12
            )
            aiRelatedByField[fieldID] = picks
            if picks.isEmpty {
                aiRelatedError = "No catalog matches returned — try a different name or tap again."
            }
        } catch {
            aiRelatedError = error.localizedDescription
        }
    }

    private func applyExerciseName(dayIndex: Int, exIndex: Int, name: String) {
        guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return }
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
            get: {
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return "" }
                return vm.days[dayIndex].exercises[exIndex].name
            },
            set: { new in
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return }
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
            get: {
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return 3 }
                return vm.days[dayIndex].exercises[exIndex].targetSets
            },
            set: { new in
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return }
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

    private func exerciseTargetRepsBinding(dayIndex: Int, exIndex: Int) -> Binding<Int> {
        Binding(
            get: {
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return 8 }
                return vm.days[dayIndex].exercises[exIndex].targetReps
            },
            set: { new in
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return }
                var copy = vm.days
                var d = copy[dayIndex]
                var e = d.exercises[exIndex]
                e.targetReps = max(1, min(30, new))
                d.exercises[exIndex] = e
                copy[dayIndex] = d
                vm.days = copy
            }
        )
    }

    private func exerciseSupersetGroupBinding(dayIndex: Int, exIndex: Int) -> Binding<Int?> {
        Binding(
            get: {
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return nil }
                return vm.days[dayIndex].exercises[exIndex].supersetGroup
            },
            set: { new in
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return }
                var copy = vm.days
                var d = copy[dayIndex]
                var e = d.exercises[exIndex]
                e.supersetGroup = new.flatMap { (1 ... 6).contains($0) ? $0 : nil }
                d.exercises[exIndex] = e
                copy[dayIndex] = d
                vm.days = copy
            }
        )
    }

    private func exerciseAmrapBinding(dayIndex: Int, exIndex: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return false }
                return vm.days[dayIndex].exercises[exIndex].isAmrap
            },
            set: { new in
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return }
                var copy = vm.days
                var d = copy[dayIndex]
                var e = d.exercises[exIndex]
                e.isAmrap = new
                d.exercises[exIndex] = e
                copy[dayIndex] = d
                vm.days = copy
            }
        )
    }

    private func exerciseWarmupBinding(dayIndex: Int, exIndex: Int) -> Binding<Bool> {
        Binding(
            get: {
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return false }
                return vm.days[dayIndex].exercises[exIndex].isWarmup
            },
            set: { new in
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return }
                var copy = vm.days
                var d = copy[dayIndex]
                var e = d.exercises[exIndex]
                e.isWarmup = new
                d.exercises[exIndex] = e
                copy[dayIndex] = d
                vm.days = copy
            }
        )
    }

    private func exerciseNotesBinding(dayIndex: Int, exIndex: Int) -> Binding<String> {
        Binding(
            get: {
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return "" }
                return vm.days[dayIndex].exercises[exIndex].notes
            },
            set: { new in
                guard exerciseIndicesAreValid(dayIndex: dayIndex, exIndex: exIndex) else { return }
                var copy = vm.days
                var d = copy[dayIndex]
                var e = d.exercises[exIndex]
                e.notes = new
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
            switch route {
            case .create, .createFromImport:
                programLibrary.setProgramInLibrary(program.id, enabled: true, catalog: bundle.mergedPrograms)
            default:
                break
            }
            dismiss()
        case .editBundled:
            if appSettings.programAdminMode {
                Task { @MainActor in
                    isPublishingCatalog = true
                    defer { isPublishingCatalog = false }
                    do {
                        let token = try await auth.accessTokenForAPI()
                        _ = try await BlueprintAPIClient.post(
                            path: "/v1/admin/catalog/programs",
                            body: program,
                            accessToken: token
                        )
                        bundle.removeBundledOverride(programId: program.id)
                        await bundle.refreshCatalogFromServer()
                        dismiss()
                    } catch {
                        publishCatalogError = error.localizedDescription
                    }
                }
            } else {
                bundle.setBundledOverride(program)
                dismiss()
            }
        }
    }
}
