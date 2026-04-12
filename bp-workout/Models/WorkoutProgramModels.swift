import Foundation

struct Exercise: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let maxWeight: String
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
