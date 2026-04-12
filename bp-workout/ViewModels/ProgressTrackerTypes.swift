import Foundation

enum ProgressChartMode: String, CaseIterable {
    case weight, volume, reprange
}

enum ProgressSortOption: String, CaseIterable {
    case sessions, gain, peak, alpha
}

/// One row for the progress list after filtering, cleaning, and sorting.
struct ProgressExerciseRow: Identifiable {
    var id: String { exercise.name }

    let exercise: ExerciseProgress
    let cleanEntries: [ProgressEntry]
    let removedCount: Int
}
