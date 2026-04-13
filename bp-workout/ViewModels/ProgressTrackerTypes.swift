import Foundation

enum ProgressChartMode: String, CaseIterable {
    case weight, volume, reprange

    var pickerLabel: String {
        switch self {
        case .weight: "Weight"
        case .volume: "Volume"
        case .reprange: "Reps"
        }
    }
}

enum ProgressSortOption: String, CaseIterable {
    case sessions, gain, peak, alpha

    var pickerLabel: String {
        switch self {
        case .sessions: "Most sessions"
        case .gain: "Biggest gain"
        case .peak: "Heaviest peak"
        case .alpha: "A–Z"
        }
    }
}

/// One row for the progress list after filtering, cleaning, and sorting.
struct ProgressExerciseRow: Identifiable {
    var id: String { exercise.name }

    let exercise: ExerciseProgress
    let cleanEntries: [ProgressEntry]
    let removedCount: Int

    /// Points that count toward load/rep trends for this exercise (excludes mirror rows under a prescribed name).
    var chartEligibleEntries: [ProgressEntry] {
        cleanEntries.filter { $0.substitutedPerformedAs == nil }
    }
}
