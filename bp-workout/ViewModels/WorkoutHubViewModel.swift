import Combine
import Foundation
import SwiftData

struct LoggedSetSnapshot: Equatable {
    var weight: Double
    var reps: Int
}

struct QuickExerciseState: Identifiable, Equatable {
    var id: String { "\(sortOrder)-\(name)" }
    let sortOrder: Int
    let name: String
    /// Peak-based plan line (may include progressive bump).
    let planDisplay: String
    /// Working sets prescribed by the program for this exercise.
    let targetSets: Int
    var workingWeight: Double
    var workingReps: Int
    var loggedSets: [LoggedSetSnapshot]
    let prHint: String?
    /// Same index = same superset round; nil if not supersetted.
    let supersetGroup: Int?
    /// Program prescribes reps to failure for each working set.
    let isAmrap: Bool
    /// Warm-up / activation — not required for “unfinished workout” warnings.
    let isWarmup: Bool
    /// Program author notes (optional).
    let programNotes: String?

    var setsRemaining: Int { max(0, targetSets - loggedSets.count) }
    var isSetsComplete: Bool { loggedSets.count >= targetSets }
}

@MainActor
final class WorkoutHubViewModel: ObservableObject {
    @Published var activeProgramId: String = ""
    @Published var dayIndex: Int = 0
    @Published private(set) var exerciseRows: [QuickExerciseState] = []

    private let bundle: BundleDataStore
    private var lastLoggedSnapshot: [LoggedWorkout] = []

    private enum DefaultsKey {
        static let programId = "workoutHub.activeProgramId"
        /// Legacy single day index; used as fallback until a per-program value exists.
        static let dayIndex = "workoutHub.dayIndex"
        static let draft = "workoutHub.draft.v1"

        static func dayIndexKey(programId: String) -> String {
            "workoutHub.dayIndex.program.\(programId)"
        }
    }

    private struct PersistedDraft: Codable, Equatable {
        struct Line: Codable, Equatable {
            var exerciseName: String
            var sortOrder: Int
            var workingWeight: Double
            var workingReps: Int
            var sets: [PersistedSet]
        }
        struct PersistedSet: Codable, Equatable {
            var weight: Double
            var reps: Int
        }
        var programId: String
        var dayLabel: String
        var lines: [Line]
    }

    init(bundle: BundleDataStore = .shared) {
        self.bundle = bundle
    }

    /// Full catalog: bundled programs, admin overrides, and user-created programs.
    var allPrograms: [WorkoutProgram] {
        bundle.mergedPrograms
    }

    /// Programs the user added to their profile (Workout tab).
    var programs: [WorkoutProgram] {
        let all = allPrograms
        let allowed = UserProgramLibrary.shared.idsInLibrary(catalogIds: all.map(\.id))
        return all.filter { allowed.contains($0.id) }
    }

    var stats: ProgramStats? {
        bundle.workoutPrograms?.stats
    }

    var activeProgram: WorkoutProgram? {
        programs.first { $0.id == activeProgramId }
    }

    var activeDay: WorkoutDay? {
        guard let p = activeProgram, dayIndex >= 0, dayIndex < p.days.count else { return nil }
        return p.days[dayIndex]
    }

    var hasLoggedSomething: Bool {
        exerciseRows.contains { !$0.loggedSets.isEmpty }
    }

    /// Exercises on this day that are below their prescribed set count (including not started). Warm-up lines are excluded.
    var incompleteExerciseRows: [QuickExerciseState] {
        exerciseRows.filter { !$0.isWarmup && $0.loggedSets.count < $0.targetSets }
    }

    var hasIncompletePlannedWork: Bool {
        !incompleteExerciseRows.isEmpty
    }

    /// User-facing detail for the incomplete-save warning (keep reasonably short).
    var incompleteSaveAlertMessage: String {
        let rows = incompleteExerciseRows
        let lines = rows.prefix(6).map { row -> String in
            if row.loggedSets.isEmpty {
                return "• \(row.name): no sets logged (plan \(row.targetSets))"
            }
            return "• \(row.name): \(row.loggedSets.count)/\(row.targetSets) sets"
        }
        let suffix: String
        if rows.count > 6 {
            suffix = "\n… and \(rows.count - 6) more"
        } else {
            suffix = ""
        }
        return "This day’s plan isn’t fully logged yet.\n\n\(lines.joined(separator: "\n"))\(suffix)\n\nExercises with no sets won’t appear in the saved workout. Save anyway?"
    }

    func onAppear() {
        bundle.loadIfNeeded()
        reconcileActiveProgramSelection()
        rebuildExerciseRows(usingLogged: lastLoggedSnapshot)
    }

    /// Call when profile library membership changes (e.g. Programs tab).
    func onLibraryChanged() {
        reconcileActiveProgramSelection()
        rebuildExerciseRows(usingLogged: lastLoggedSnapshot)
    }

    /// Call when merged program catalog changes (custom programs or bundled overrides).
    func onCatalogChanged() {
        reconcileActiveProgramSelection()
        rebuildExerciseRows(usingLogged: lastLoggedSnapshot)
    }

    func syncLoggedWorkouts(_ workouts: [LoggedWorkout]) {
        lastLoggedSnapshot = workouts
        rebuildExerciseRows(usingLogged: workouts)
    }

    func selectProgram(id: String) {
        guard id != activeProgramId else { return }
        clearDraft()
        activeProgramId = id
        UserDefaults.standard.set(id, forKey: DefaultsKey.programId)
        let days = programs.first(where: { $0.id == id })?.days.count ?? 0
        let saved = restoredDayIndex(forProgramId: id)
        dayIndex = clampDayIndex(saved, days: days)
        UserDefaults.standard.set(dayIndex, forKey: DefaultsKey.dayIndexKey(programId: id))
        rebuildExerciseRows(usingLogged: lastLoggedSnapshot)
    }

    func setDayIndex(_ index: Int) {
        guard let p = activeProgram else { return }
        let next = clampDayIndex(index, days: p.days.count)
        guard next != dayIndex else { return }
        dayIndex = next
        UserDefaults.standard.set(next, forKey: DefaultsKey.dayIndexKey(programId: activeProgramId))
        UserDefaults.standard.set(next, forKey: DefaultsKey.dayIndex)
        clearDraft()
        rebuildExerciseRows(usingLogged: lastLoggedSnapshot)
    }

    func nudgeWeight(for rowId: String, delta: Double) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        let v = max(0, exerciseRows[i].workingWeight + delta)
        exerciseRows[i].workingWeight = (v * 4).rounded() / 4
        persistDraft()
    }

    func nudgeReps(for rowId: String, delta: Int) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        exerciseRows[i].workingReps = max(1, exerciseRows[i].workingReps + delta)
        persistDraft()
    }

    func logSet(for rowId: String) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        guard exerciseRows[i].loggedSets.count < exerciseRows[i].targetSets else { return }
        let w = exerciseRows[i].workingWeight
        let r = exerciseRows[i].workingReps
        guard r > 0 else { return }
        exerciseRows[i].loggedSets.append(LoggedSetSnapshot(weight: w, reps: r))
        persistDraft()
    }

    func repeatLastSet(for rowId: String) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        guard exerciseRows[i].loggedSets.count < exerciseRows[i].targetSets else { return }
        guard let last = exerciseRows[i].loggedSets.last else { return }
        exerciseRows[i].workingWeight = last.weight
        exerciseRows[i].workingReps = last.reps
        exerciseRows[i].loggedSets.append(LoggedSetSnapshot(weight: last.weight, reps: last.reps))
        persistDraft()
    }

    func removeLastSet(for rowId: String) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        guard !exerciseRows[i].loggedSets.isEmpty else { return }
        exerciseRows[i].loggedSets.removeLast()
        persistDraft()
    }

    func finishAndSave(modelContext: ModelContext) {
        guard let p = activeProgram, let day = activeDay else { return }
        let rows = exerciseRows.filter { !$0.loggedSets.isEmpty }
        guard !rows.isEmpty else { return }

        let workout = LoggedWorkout(
            date: .now,
            programName: p.name,
            dayLabel: day.label,
            notes: nil
        )
        for row in rows.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let ex = LoggedExercise(name: row.name, sortOrder: row.sortOrder)
            for (idx, s) in row.loggedSets.enumerated() {
                ex.sets.append(LoggedSet(weight: s.weight, reps: s.reps, order: idx))
            }
            workout.exercises.append(ex)
        }
        modelContext.insert(workout)
        clearDraft()
        // Keep suggestions in sync before @Query delivers the new row.
        lastLoggedSnapshot = ([workout] + lastLoggedSnapshot).sorted { $0.date > $1.date }
        rebuildExerciseRows(usingLogged: lastLoggedSnapshot)
    }

    // MARK: - Private

    private func reconcileActiveProgramSelection() {
        let d = UserDefaults.standard
        guard !programs.isEmpty else {
            activeProgramId = ""
            dayIndex = 0
            return
        }
        if let saved = d.string(forKey: DefaultsKey.programId), !saved.isEmpty,
           programs.contains(where: { $0.id == saved }) {
            activeProgramId = saved
        } else {
            activeProgramId = programs[0].id
            d.set(activeProgramId, forKey: DefaultsKey.programId)
        }
        if let p = activeProgram {
            let saved = restoredDayIndex(forProgramId: activeProgramId)
            dayIndex = clampDayIndex(saved, days: p.days.count)
            d.set(dayIndex, forKey: DefaultsKey.dayIndexKey(programId: activeProgramId))
        }
    }

    private func rebuildExerciseRows(usingLogged logged: [LoggedWorkout]) {
        guard let day = activeDay, let program = activeProgram else {
            exerciseRows = []
            return
        }
        let bundleData = bundle.progressBundle
        var rows: [QuickExerciseState] = []
        for (idx, ex) in day.exercises.enumerated() {
            let sug = WorkoutPrefill.suggest(
                exerciseName: ex.name,
                templateMax: ex.maxWeight,
                loggedWorkouts: logged,
                progressBundle: bundleData,
                prescriptionIsAmrap: ex.prescriptionIsAmrap,
                prescriptionIsWarmup: ex.prescriptionIsWarmup
            )
            let prescribed = ex.prescribedSets
            var state = QuickExerciseState(
                sortOrder: idx,
                name: ex.name,
                planDisplay: sug.planDisplay,
                targetSets: prescribed,
                workingWeight: sug.weight,
                workingReps: sug.reps,
                loggedSets: [],
                prHint: sug.prHint,
                supersetGroup: ex.supersetGroup,
                isAmrap: ex.prescriptionIsAmrap,
                isWarmup: ex.prescriptionIsWarmup,
                programNotes: ex.trimmedProgramNotes
            )
            if let draft = loadDraft(), draft.programId == program.id, draft.dayLabel == day.label,
               let line = draft.lines.first(where: { $0.exerciseName == ex.name && $0.sortOrder == idx }) {
                state.workingWeight = line.workingWeight
                state.workingReps = line.workingReps
                let loaded = line.sets.map { LoggedSetSnapshot(weight: $0.weight, reps: $0.reps) }
                state.loggedSets = Array(loaded.prefix(prescribed))
            }
            rows.append(state)
        }
        exerciseRows = rows
    }

    private func loadDraft() -> PersistedDraft? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.draft) else { return nil }
        return try? JSONDecoder().decode(PersistedDraft.self, from: data)
    }

    private func persistDraft() {
        guard let program = activeProgram, let day = activeDay else { return }
        let lines: [PersistedDraft.Line] = exerciseRows.map { r in
            PersistedDraft.Line(
                exerciseName: r.name,
                sortOrder: r.sortOrder,
                workingWeight: r.workingWeight,
                workingReps: r.workingReps,
                sets: r.loggedSets.map { PersistedDraft.PersistedSet(weight: $0.weight, reps: $0.reps) }
            )
        }
        let draft = PersistedDraft(programId: program.id, dayLabel: day.label, lines: lines)
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.draft)
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.draft)
    }

    private func restoredDayIndex(forProgramId id: String) -> Int {
        let d = UserDefaults.standard
        let key = DefaultsKey.dayIndexKey(programId: id)
        if d.object(forKey: key) != nil {
            return d.integer(forKey: key)
        }
        return d.integer(forKey: DefaultsKey.dayIndex)
    }

    private func clampDayIndex(_ index: Int, days: Int) -> Int {
        guard days > 0 else { return 0 }
        return min(max(0, index), days - 1)
    }
}
