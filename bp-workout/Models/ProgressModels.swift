import Foundation

struct ProgressEntry: Codable, Hashable, Identifiable {
    var id: String {
        let sub = substitutedPerformedAs ?? ""
        return "\(date)|\(program)|\(weight)|\(reps)|\(dayTitle)|\(sub)"
    }

    let date: String
    let weight: Double
    let reps: Int
    let maxReps: Int
    let program: String
    let dayTitle: String
    /// When set, this point appears under the **prescribed** exercise’s history; value is the **performed** exercise name (actual movement).
    let substitutedPerformedAs: String?

    init(
        date: String,
        weight: Double,
        reps: Int,
        maxReps: Int,
        program: String,
        dayTitle: String,
        substitutedPerformedAs: String? = nil
    ) {
        self.date = date
        self.weight = weight
        self.reps = reps
        self.maxReps = maxReps
        self.program = program
        self.dayTitle = dayTitle
        self.substitutedPerformedAs = substitutedPerformedAs
    }
}

struct ExerciseProgress: Codable, Hashable, Identifiable {
    var id: String { name }

    let name: String
    let sessionCount: Int
    let peakWeight: Double
    let firstWeight: Double
    let lastWeight: Double
    let entries: [ProgressEntry]
}

struct ProgressDataBundle: Codable {
    let exerciseProgressData: [ExerciseProgress]
    let programColors: [String: String]
}

enum ExerciseNameNormalizer {
    static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
