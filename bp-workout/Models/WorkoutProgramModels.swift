import Foundation

struct Exercise: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let maxWeight: String
    /// Prescribed working sets for this lift; omit in JSON to default to 3.
    let targetSets: Int?

    /// Clamped prescription used for logging UI (1…20).
    var prescribedSets: Int {
        let n = targetSets ?? 3
        return max(1, min(n, 20))
    }
}

struct WorkoutDay: Codable, Hashable, Identifiable {
    var id: String { label }
    let label: String
    let exercises: [Exercise]
}

struct WorkoutProgram: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let period: String
    let dateRange: String
    let days: [WorkoutDay]
    let color: String
    let isUserCreated: Bool?

    /// Marketplace accent when the program editor does not expose a custom color.
    static let defaultAccentHex = "#66bfcc"
}

struct ProgramStats: Codable, Hashable {
    let totalPrograms: Int
    let totalMonths: Int
    let totalWorkoutDays: Int
    let dateRange: String
}

struct WorkoutProgramsBundle: Codable {
    let programs: [WorkoutProgram]
    let stats: ProgramStats
}
