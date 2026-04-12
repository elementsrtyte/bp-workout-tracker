import Combine
import Foundation

@MainActor
final class SettingsViewModel: ObservableObject {
    private let bundle: BundleDataStore

    init(bundle: BundleDataStore = .shared) {
        self.bundle = bundle
    }

    func onAppear() {
        bundle.loadIfNeeded()
    }

    func mergedEntries(loggedWorkouts: [LoggedWorkout]) -> [ProgressEntry] {
        guard let b = bundle.progressBundle else { return [] }
        let user = LoggedWorkoutProgressExport.entriesByExerciseName(workouts: loggedWorkouts)
        let merged = ProgressMergeService.mergedExerciseProgress(bundle: b, userEntriesByExercise: user)
        return merged.flatMap(\.entries)
    }

    func minRepsExcludedCount(loggedWorkouts: [LoggedWorkout], appSettings: AppSettings) -> Int {
        mergedEntries(loggedWorkouts: loggedWorkouts).filter { $0.reps < appSettings.minReps }.count
    }

    func anomalyFlaggedCount(loggedWorkouts: [LoggedWorkout], appSettings: AppSettings) -> Int {
        guard appSettings.filterAnomalies else { return 0 }
        guard let b = bundle.progressBundle else { return 0 }
        let user = LoggedWorkoutProgressExport.entriesByExerciseName(workouts: loggedWorkouts)
        let merged = ProgressMergeService.mergedExerciseProgress(bundle: b, userEntriesByExercise: user)
        return merged.reduce(0) { partial, ex in
            partial + AnomalyFilter.countAnomalies(entries: ex.entries, sensitivity: appSettings.anomalySensitivity)
        }
    }
}
