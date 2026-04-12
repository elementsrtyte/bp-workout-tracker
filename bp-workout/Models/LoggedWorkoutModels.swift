import Foundation
import SwiftData

@Model
final class LoggedWorkout {
    var id: UUID
    var date: Date
    var programName: String?
    var dayLabel: String?
    var notes: String?
    @Relationship(deleteRule: .cascade, inverse: \LoggedExercise.workout)
    var exercises: [LoggedExercise]

    init(
        id: UUID = UUID(),
        date: Date = .now,
        programName: String? = nil,
        dayLabel: String? = nil,
        notes: String? = nil,
        exercises: [LoggedExercise] = []
    ) {
        self.id = id
        self.date = date
        self.programName = programName
        self.dayLabel = dayLabel
        self.notes = notes
        self.exercises = exercises
    }
}

@Model
final class LoggedExercise {
    var id: UUID
    var name: String
    var sortOrder: Int
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.exercise)
    var sets: [LoggedSet]
    var workout: LoggedWorkout?

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0, sets: [LoggedSet] = []) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.sets = sets
    }
}

@Model
final class LoggedSet {
    var id: UUID
    var weight: Double
    var reps: Int
    var order: Int
    var exercise: LoggedExercise?

    init(id: UUID = UUID(), weight: Double, reps: Int, order: Int = 0) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.order = order
    }
}

extension LoggedWorkout {
    /// Subtitle for list rows (Log tab).
    var listSubtitle: String {
        let parts = [programName, dayLabel].compactMap { $0 }.joined(separator: " · ")
        let ex = exercises.count
        return parts.isEmpty ? "\(ex) exercises" : "\(parts) · \(ex) exercises"
    }
}

enum LoggedWorkoutProgressExport {
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Each logged set becomes one `ProgressEntry` (reps and maxReps both set for that set).
    static func entriesByExerciseName(workouts: [LoggedWorkout]) -> [String: [ProgressEntry]] {
        var result: [String: [ProgressEntry]] = [:]
        for w in workouts {
            let dateString = dayFormatter.string(from: w.date)
            let program = w.programName ?? "User Logged"
            let dayTitle = (w.dayLabel ?? "Session") + "//User"
            let sortedEx = w.exercises.sorted { $0.sortOrder < $1.sortOrder }
            for ex in sortedEx {
                let sortedSets = ex.sets.sorted { $0.order < $1.order }
                for s in sortedSets {
                    let entry = ProgressEntry(
                        date: dateString,
                        weight: s.weight,
                        reps: s.reps,
                        maxReps: s.reps,
                        program: program,
                        dayTitle: dayTitle
                    )
                    result[ex.name, default: []].append(entry)
                }
            }
        }
        return result
    }
}
