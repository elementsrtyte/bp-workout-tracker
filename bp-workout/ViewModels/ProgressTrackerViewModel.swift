import Combine
import Foundation

@MainActor
final class ProgressTrackerViewModel: ObservableObject {
    @Published var search: String = ""
    @Published var sortBy: ProgressSortOption = .sessions
    @Published var programFilter: String = "all"
    @Published var chartMode: ProgressChartMode = .weight

    private let bundle: BundleDataStore

    init(bundle: BundleDataStore = .shared) {
        self.bundle = bundle
    }

    func onAppear() {
        bundle.loadIfNeeded()
    }

    static let programFilterOptions: [String] = [
        "Program 1", "Program 2", "Program 3", "Program 4", "Program 5", "Program 6", "User Logged",
    ]

    func mergedProgramColors() -> [String: String] {
        var m = bundle.progressBundle?.programColors ?? [:]
        m["User Logged"] = "#66bfcc"
        m["Program 6"] = "#F59E0B"
        return m
    }

    func filteredRows(
        loggedWorkouts: [LoggedWorkout],
        appSettings: AppSettings
    ) -> [ProgressExerciseRow] {
        guard let b = bundle.progressBundle else { return [] }
        let user = LoggedWorkoutProgressExport.entriesByExerciseName(workouts: loggedWorkouts)
        let merged = ProgressMergeService.mergedExerciseProgress(bundle: b, userEntriesByExercise: user)

        let cleaned: [(ex: ExerciseProgress, clean: [ProgressEntry], removed: Int)] = merged.map { ex in
            let clean = AnomalyFilter.getCleanEntries(
                entries: ex.entries,
                filterEnabled: appSettings.filterAnomalies,
                sensitivity: appSettings.anomalySensitivity,
                minReps: appSettings.minReps
            )
            let removed = ex.entries.count - clean.count
            return (ex, clean, removed)
        }

        var list = cleaned
        if programFilter != "all" {
            list = list.filter { item in
                item.clean.contains { $0.program == programFilter }
            }
        }
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter { $0.ex.name.lowercased().contains(q) }
        }
        switch sortBy {
        case .sessions:
            list.sort {
                let a = $0.clean.filter { $0.substitutedPerformedAs == nil }.count
                let b = $1.clean.filter { $0.substitutedPerformedAs == nil }.count
                return a > b
            }
        case .gain:
            list.sort {
                let ea = $0.clean.filter { $0.substitutedPerformedAs == nil }
                let eb = $1.clean.filter { $0.substitutedPerformedAs == nil }
                return ProgressMetrics.pctChange(entries: ea) > ProgressMetrics.pctChange(entries: eb)
            }
        case .peak:
            list.sort {
                let pa = $0.clean.filter { $0.substitutedPerformedAs == nil }.map(\.weight).max() ?? 0
                let pb = $1.clean.filter { $0.substitutedPerformedAs == nil }.map(\.weight).max() ?? 0
                return pa > pb
            }
        case .alpha:
            list.sort { $0.ex.name.localizedCaseInsensitiveCompare($1.ex.name) == .orderedAscending }
        }

        return list.map {
            ProgressExerciseRow(exercise: $0.ex, cleanEntries: $0.clean, removedCount: $0.removed)
        }
    }
}
