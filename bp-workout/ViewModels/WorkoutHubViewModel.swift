import Combine
import Foundation
import SwiftData

enum LogSetOutcome: Equatable {
    case noop
    case loggedSetContinuing
    case finishedExercise
}

struct LoggedSetSnapshot: Equatable {
    var weight: Double
    var reps: Int
}

struct QuickExerciseState: Identifiable, Equatable {
    /// Stable identity for this line on the training day (survives session exercise renames).
    var id: String { "slot-\(sortOrder)" }
    let sortOrder: Int
    /// From the program template (unchanged for this session).
    let prescribedName: String
    /// May differ when the user substitutes equipment for today only.
    var name: String
    /// Peak-based plan line (may include progressive bump).
    var planDisplay: String
    /// Working sets prescribed by the program for this exercise.
    let targetSets: Int
    var workingWeight: Double
    var workingReps: Int
    var loggedSets: [LoggedSetSnapshot]
    var prHint: String?
    /// Same index = same superset round; nil if not supersetted.
    let supersetGroup: Int?
    /// Program prescribes reps to failure for each working set.
    let isAmrap: Bool
    /// Warm-up / activation — not required for “unfinished workout” warnings.
    let isWarmup: Bool
    /// Program author notes (optional).
    let programNotes: String?
    /// Fixed rep target from program (nil for AMRAP or unspecified).
    let prescribedTargetReps: Int?

    var setsRemaining: Int { max(0, targetSets - loggedSets.count) }
    var isSetsComplete: Bool { loggedSets.count >= targetSets }
    var isSubstituted: Bool { name != prescribedName }
}

@MainActor
final class WorkoutHubViewModel: ObservableObject {
    @Published var activeProgramId: String = ""
    @Published var dayIndex: Int = 0
    @Published private(set) var exerciseRows: [QuickExerciseState] = []
    /// Wall-clock start for the current in-progress session (persisted with draft).
    @Published private(set) var sessionWallClockStart: Date?
    /// Seconds remaining for rest between sets; nil when idle.
    @Published private(set) var restSecondsRemaining: Int?

    private let bundle: BundleDataStore
    private var lastLoggedSnapshot: [LoggedWorkout] = []
    private var restCountdownTask: Task<Void, Never>?
    /// Rest duration after logging a set when more sets remain (from Settings).
    var restBetweenSetsSeconds: Int = 90

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
        var sessionStartedAt: Date?
        struct Line: Codable, Equatable {
            var sortOrder: Int
            /// Display / logging name (may be a session substitute).
            var exerciseName: String
            /// Program template name when `exerciseName` was substituted; omitted when equal.
            var prescribedName: String?
            var workingWeight: Double
            var workingReps: Int
            var sets: [PersistedSet]

            enum CodingKeys: String, CodingKey {
                case sortOrder, exerciseName, prescribedName, workingWeight, workingReps, sets
            }

            init(
                sortOrder: Int,
                exerciseName: String,
                prescribedName: String?,
                workingWeight: Double,
                workingReps: Int,
                sets: [PersistedSet]
            ) {
                self.sortOrder = sortOrder
                self.exerciseName = exerciseName
                self.prescribedName = prescribedName
                self.workingWeight = workingWeight
                self.workingReps = workingReps
                self.sets = sets
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                sortOrder = try c.decode(Int.self, forKey: .sortOrder)
                exerciseName = try c.decode(String.self, forKey: .exerciseName)
                prescribedName = try c.decodeIfPresent(String.self, forKey: .prescribedName)
                workingWeight = try c.decode(Double.self, forKey: .workingWeight)
                workingReps = try c.decode(Int.self, forKey: .workingReps)
                sets = try c.decode([PersistedSet].self, forKey: .sets)
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(sortOrder, forKey: .sortOrder)
                try c.encode(exerciseName, forKey: .exerciseName)
                if let p = prescribedName, p != exerciseName {
                    try c.encode(p, forKey: .prescribedName)
                }
                try c.encode(workingWeight, forKey: .workingWeight)
                try c.encode(workingReps, forKey: .workingReps)
                try c.encode(sets, forKey: .sets)
            }
        }
        struct PersistedSet: Codable, Equatable {
            var weight: Double
            var reps: Int
        }

        var programId: String
        var dayLabel: String
        var lines: [Line]

        enum CodingKeys: String, CodingKey {
            case sessionStartedAt
            case programId
            case dayLabel
            case lines
        }

        init(programId: String, dayLabel: String, sessionStartedAt: Date?, lines: [Line]) {
            self.programId = programId
            self.dayLabel = dayLabel
            self.sessionStartedAt = sessionStartedAt
            self.lines = lines
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            programId = try c.decode(String.self, forKey: .programId)
            dayLabel = try c.decode(String.self, forKey: .dayLabel)
            sessionStartedAt = try c.decodeIfPresent(Date.self, forKey: .sessionStartedAt)
            lines = try c.decode([Line].self, forKey: .lines)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(programId, forKey: .programId)
            try c.encode(dayLabel, forKey: .dayLabel)
            try c.encodeIfPresent(sessionStartedAt, forKey: .sessionStartedAt)
            try c.encode(lines, forKey: .lines)
        }
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

    /// Parses "185", "185.5", "BW", comma decimals; ignores incomplete input.
    func setWorkingWeightFromString(for rowId: String, raw: String) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let lower = t.lowercased()
        if lower == "bw" || lower == "bodyweight" {
            exerciseRows[i].workingWeight = 0
            persistDraft()
            return
        }
        let norm = t.replacingOccurrences(of: ",", with: ".")
        guard let v = Double(norm) else { return }
        exerciseRows[i].workingWeight = max(0, (v * 4).rounded() / 4)
        persistDraft()
    }

    func nudgeReps(for rowId: String, delta: Int) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        exerciseRows[i].workingReps = max(1, exerciseRows[i].workingReps + delta)
        persistDraft()
    }

    func logSet(for rowId: String) -> LogSetOutcome {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return .noop }
        guard exerciseRows[i].loggedSets.count < exerciseRows[i].targetSets else { return .noop }
        let w = exerciseRows[i].workingWeight
        let r = exerciseRows[i].workingReps
        guard r > 0 else { return .noop }
        exerciseRows[i].loggedSets.append(LoggedSetSnapshot(weight: w, reps: r))
        let nowComplete = exerciseRows[i].loggedSets.count >= exerciseRows[i].targetSets
        persistDraft()
        if !nowComplete {
            startRestBetweenSetsIfConfigured()
            return .loggedSetContinuing
        }
        return .finishedExercise
    }

    func skipRestTimer() {
        restCountdownTask?.cancel()
        restCountdownTask = nil
        restSecondsRemaining = nil
        RestTimerNotificationScheduler.cancelScheduled()
    }

    private func startRestBetweenSetsIfConfigured() {
        let sec = max(0, restBetweenSetsSeconds)
        guard sec > 0 else { return }
        skipRestTimer()
        restSecondsRemaining = sec
        RestTimerNotificationScheduler.scheduleRestComplete(after: TimeInterval(sec))
        restCountdownTask = Task { @MainActor in
            for remaining in stride(from: sec, through: 0, by: -1) {
                if Task.isCancelled { return }
                self.restSecondsRemaining = remaining
                if remaining == 0 { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            if !Task.isCancelled {
                self.restSecondsRemaining = nil
                RestTimerNotificationScheduler.cancelScheduled()
            }
        }
    }

    func repeatLastSet(for rowId: String) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        guard exerciseRows[i].loggedSets.count < exerciseRows[i].targetSets else { return }
        guard let last = exerciseRows[i].loggedSets.last else { return }
        exerciseRows[i].workingWeight = last.weight
        exerciseRows[i].workingReps = last.reps
        exerciseRows[i].loggedSets.append(LoggedSetSnapshot(weight: last.weight, reps: last.reps))
        let nowComplete = exerciseRows[i].loggedSets.count >= exerciseRows[i].targetSets
        persistDraft()
        if !nowComplete {
            startRestBetweenSetsIfConfigured()
        }
    }

    func removeLastSet(for rowId: String) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        guard !exerciseRows[i].loggedSets.isEmpty else { return }
        exerciseRows[i].loggedSets.removeLast()
        persistDraft()
    }

    /// Updates a previously logged set (e.g. typo) without undoing newer sets.
    func replaceLoggedSet(for rowId: String, setIndex: Int, weight: Double, reps: Int) {
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        guard setIndex >= 0, setIndex < exerciseRows[i].loggedSets.count else { return }
        guard reps > 0 else { return }
        let w = max(0, (weight * 4).rounded() / 4)
        exerciseRows[i].loggedSets[setIndex] = LoggedSetSnapshot(weight: w, reps: reps)
        persistDraft()
    }

    /// Swap the exercise for **this session only** (does not edit the saved program). Recomputes weight/reps hints from history.
    func applySessionExerciseSubstitution(rowId: String, newDisplayName: String, clearLoggedSets: Bool) {
        guard let day = activeDay, let program = activeProgram else { return }
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        guard i >= 0, i < day.exercises.count else { return }
        let trimmed = newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !exerciseRows[i].loggedSets.isEmpty, !clearLoggedSets { return }

        let ex = day.exercises[i]
        let sug = WorkoutPrefill.suggest(
            exerciseName: trimmed,
            templateMax: ex.maxWeight,
            loggedWorkouts: lastLoggedSnapshot,
            progressBundle: bundle.progressBundle,
            prescriptionIsAmrap: ex.prescriptionIsAmrap,
            prescriptionIsWarmup: ex.prescriptionIsWarmup,
            templateTargetReps: ex.prescribedRepTarget
        )
        exerciseRows[i].name = trimmed
        exerciseRows[i].planDisplay = sug.planDisplay
        exerciseRows[i].prHint = sug.prHint
        exerciseRows[i].workingWeight = sug.weight
        exerciseRows[i].workingReps = sug.reps
        exerciseRows[i].loggedSets = []
        exerciseRows = exerciseRows
        persistDraft()
    }

    func revertSessionExerciseSubstitution(rowId: String) {
        guard let day = activeDay, let program = activeProgram else { return }
        guard let i = exerciseRows.firstIndex(where: { $0.id == rowId }) else { return }
        guard i >= 0, i < day.exercises.count else { return }
        if !exerciseRows[i].loggedSets.isEmpty { return }
        let ex = day.exercises[i]
        let sug = WorkoutPrefill.suggest(
            exerciseName: ex.name,
            templateMax: ex.maxWeight,
            loggedWorkouts: lastLoggedSnapshot,
            progressBundle: bundle.progressBundle,
            prescriptionIsAmrap: ex.prescriptionIsAmrap,
            prescriptionIsWarmup: ex.prescriptionIsWarmup,
            templateTargetReps: ex.prescribedRepTarget
        )
        exerciseRows[i].name = ex.name
        exerciseRows[i].planDisplay = sug.planDisplay
        exerciseRows[i].prHint = sug.prHint
        exerciseRows[i].workingWeight = sug.weight
        exerciseRows[i].workingReps = sug.reps
        exerciseRows[i].loggedSets = []
        exerciseRows = exerciseRows
        persistDraft()
    }

    @discardableResult
    func finishAndSave(modelContext: ModelContext) -> Bool {
        guard let p = activeProgram, let day = activeDay else { return false }
        let rows = exerciseRows.filter { !$0.loggedSets.isEmpty }
        guard !rows.isEmpty else { return false }

        let workout = LoggedWorkout(
            date: .now,
            programId: p.id,
            programName: p.name,
            dayLabel: day.label,
            notes: nil
        )
        for row in rows.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            let ex = LoggedExercise(
                name: row.name,
                prescribedName: row.isSubstituted ? row.prescribedName : nil,
                sortOrder: row.sortOrder
            )
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
        Task { await BlueprintWorkoutSyncClient.push(workout) }
        return true
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
            sessionWallClockStart = nil
            return
        }
        let bundleData = bundle.progressBundle
        let persistedDraft = loadDraft()
        var rows: [QuickExerciseState] = []
        for (idx, ex) in day.exercises.enumerated() {
            let sug = WorkoutPrefill.suggest(
                exerciseName: ex.name,
                templateMax: ex.maxWeight,
                loggedWorkouts: logged,
                progressBundle: bundleData,
                prescriptionIsAmrap: ex.prescriptionIsAmrap,
                prescriptionIsWarmup: ex.prescriptionIsWarmup,
                templateTargetReps: ex.prescribedRepTarget
            )
            let prescribed = ex.prescribedSets
            var state = QuickExerciseState(
                sortOrder: idx,
                prescribedName: ex.name,
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
                programNotes: ex.trimmedProgramNotes,
                prescribedTargetReps: ex.prescribedRepTarget
            )
            if let draft = persistedDraft, draft.programId == program.id, draft.dayLabel == day.label,
               let line = draft.lines.first(where: { $0.sortOrder == idx }) {
                let draftName = line.exerciseName
                state.name = draftName
                if draftName != ex.name {
                    let subSug = WorkoutPrefill.suggest(
                        exerciseName: draftName,
                        templateMax: ex.maxWeight,
                        loggedWorkouts: logged,
                        progressBundle: bundleData,
                        prescriptionIsAmrap: ex.prescriptionIsAmrap,
                        prescriptionIsWarmup: ex.prescriptionIsWarmup,
                        templateTargetReps: ex.prescribedRepTarget
                    )
                    state.planDisplay = subSug.planDisplay
                    state.prHint = subSug.prHint
                }
                state.workingWeight = line.workingWeight
                state.workingReps = line.workingReps
                let loaded = line.sets.map { LoggedSetSnapshot(weight: $0.weight, reps: $0.reps) }
                state.loggedSets = Array(loaded.prefix(prescribed))
            }
            rows.append(state)
        }
        exerciseRows = rows
        sessionWallClockStart = persistedDraft?.sessionStartedAt
    }

    private func loadDraft() -> PersistedDraft? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.draft) else { return nil }
        return try? JSONDecoder().decode(PersistedDraft.self, from: data)
    }

    private func persistDraft() {
        guard let program = activeProgram, let day = activeDay else { return }
        let hasSetsNow = exerciseRows.contains { !$0.loggedSets.isEmpty }
        let previousStart = loadDraft()?.sessionStartedAt
        let sessionStartedAt: Date? = hasSetsNow ? (previousStart ?? Date()) : nil
        sessionWallClockStart = sessionStartedAt
        let lines: [PersistedDraft.Line] = exerciseRows.map { r in
            PersistedDraft.Line(
                sortOrder: r.sortOrder,
                exerciseName: r.name,
                prescribedName: r.prescribedName == r.name ? nil : r.prescribedName,
                workingWeight: r.workingWeight,
                workingReps: r.workingReps,
                sets: r.loggedSets.map { PersistedDraft.PersistedSet(weight: $0.weight, reps: $0.reps) }
            )
        }
        let draft = PersistedDraft(
            programId: program.id,
            dayLabel: day.label,
            sessionStartedAt: sessionStartedAt,
            lines: lines
        )
        if let data = try? JSONEncoder().encode(draft) {
            UserDefaults.standard.set(data, forKey: DefaultsKey.draft)
        }
    }

    private func clearDraft() {
        UserDefaults.standard.removeObject(forKey: DefaultsKey.draft)
        sessionWallClockStart = nil
        skipRestTimer()
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
