import ActivityKit
import Foundation

/// Must match `WorkoutWidgetExtension/WorkoutRestAttributes.swift` exactly.
struct WorkoutRestAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var restEnd: Date
        var exerciseName: String
        var setNumber: Int
        var totalSets: Int
        var targetReps: Int
        var isAmrap: Bool
        var weightLabel: String
        var isOvertime: Bool
        var overtimeSeconds: Int
    }

    var dayLabel: String
    var programName: String
}
