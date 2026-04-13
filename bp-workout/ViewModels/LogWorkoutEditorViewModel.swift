import Combine
import Foundation
import SwiftData

@MainActor
final class LogWorkoutEditorViewModel: ObservableObject {
    @Published var date: Date = .now
    @Published var programName: String = ""
    @Published var dayLabel: String = ""
    @Published var notes: String = ""
    @Published var exercises: [DraftExercise] = []

    private let template: LogWorkoutTemplate?
    private let bundle: BundleDataStore

    init(template: LogWorkoutTemplate?, bundle: BundleDataStore = .shared) {
        self.template = template
        self.bundle = bundle
    }

    var canSave: Bool {
        exercises.contains { ex in
            !ex.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && ex.sets.contains { s in
                    let w = Double(s.weight.trimmingCharacters(in: .whitespaces)) ?? -1
                    let r = Int(s.reps.trimmingCharacters(in: .whitespaces)) ?? 0
                    return w >= 0 && r > 0
                }
        }
    }

    func onAppear(loggedWorkoutsForPrefill: [LoggedWorkout] = []) {
        bundle.loadIfNeeded()
        applyTemplateIfNeeded(loggedWorkouts: loggedWorkoutsForPrefill)
    }

    private func applyTemplateIfNeeded(loggedWorkouts: [LoggedWorkout]) {
        guard let t = template, exercises.isEmpty else { return }
        if let pn = t.programName { programName = pn }
        if let dl = t.dayLabel { dayLabel = dl }
        let programs = bundle.mergedPrograms
        guard let programName = t.programName,
              let dayLabel = t.dayLabel,
              let p = programs.first(where: { $0.name == programName }),
              let day = p.days.first(where: { $0.label == dayLabel })
        else { return }
        let progress = bundle.progressBundle
        exercises = day.exercises.map { ex in
            let sug = WorkoutPrefill.suggest(
                exerciseName: ex.name,
                templateMax: ex.maxWeight,
                loggedWorkouts: loggedWorkouts,
                progressBundle: progress
            )
            let wStr = sug.weight == 0 ? "0" : WorkoutPrefill.formatWeight(sug.weight)
            let rStr = "\(sug.reps)"
            let n = ex.prescribedSets
            let sets = (0 ..< n).map { _ in DraftSet(weight: wStr, reps: rStr) }
            return DraftExercise(name: ex.name, sets: sets)
        }
    }

    func save(modelContext: ModelContext, onComplete: () -> Void) {
        let workout = LoggedWorkout(
            date: date,
            programName: programName.isEmpty ? nil : programName,
            dayLabel: dayLabel.isEmpty ? nil : dayLabel,
            notes: notes.isEmpty ? nil : notes
        )
        var order = 0
        for dex in exercises {
            let trimmed = dex.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let ex = LoggedExercise(name: trimmed, sortOrder: order)
            order += 1
            var sOrder = 0
            for ds in dex.sets {
                guard let w = Double(ds.weight.trimmingCharacters(in: .whitespaces)),
                      let r = Int(ds.reps.trimmingCharacters(in: .whitespaces)),
                      w >= 0, r > 0
                else { continue }
                let set = LoggedSet(weight: w, reps: r, order: sOrder)
                sOrder += 1
                ex.sets.append(set)
            }
            guard !ex.sets.isEmpty else { continue }
            workout.exercises.append(ex)
        }
        guard !workout.exercises.isEmpty else { return }
        modelContext.insert(workout)
        onComplete()
    }
}

// MARK: - Draft models (owned by editor VM layer)

struct DraftExercise: Identifiable {
    let id: UUID
    var name: String
    var sets: [DraftSet]

    init(id: UUID = UUID(), name: String, sets: [DraftSet]) {
        self.id = id
        self.name = name
        self.sets = sets
    }
}

struct DraftSet: Identifiable {
    let id: UUID
    var weight: String
    var reps: String

    init(id: UUID = UUID(), weight: String, reps: String) {
        self.id = id
        self.weight = weight
        self.reps = reps
    }
}
