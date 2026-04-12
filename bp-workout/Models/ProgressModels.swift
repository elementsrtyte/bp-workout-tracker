import Foundation

struct ProgressEntry: Codable, Hashable, Identifiable {
    var id: String { "\(date)|\(program)|\(weight)|\(reps)|\(dayTitle)" }

    let date: String
    let weight: Double
    let reps: Int
    let maxReps: Int
    let program: String
    let dayTitle: String
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
