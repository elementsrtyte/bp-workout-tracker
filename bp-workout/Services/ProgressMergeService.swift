import Foundation

enum ProgressMergeService {
    static func mergedExerciseProgress(
        bundle: ProgressDataBundle,
        userEntriesByExercise: [String: [ProgressEntry]]
    ) -> [ExerciseProgress] {
        var buckets: [String: (displayName: String, entries: [ProgressEntry])] = [:]

        for ex in bundle.exerciseProgressData {
            let k = ExerciseNameNormalizer.key(ex.name)
            buckets[k] = (ex.name, ex.entries)
        }

        for (name, entries) in userEntriesByExercise {
            let k = ExerciseNameNormalizer.key(name)
            if var b = buckets[k] {
                b.entries.append(contentsOf: entries)
                buckets[k] = b
            } else {
                buckets[k] = (name, entries)
            }
        }

        return buckets.values.map { pair in
            let sorted = pair.entries.sorted { $0.date < $1.date }
            let weights = sorted.map(\.weight)
            let peak = weights.max() ?? 0
            let first = sorted.first?.weight ?? 0
            let last = sorted.last?.weight ?? 0
            return ExerciseProgress(
                name: pair.displayName,
                sessionCount: sorted.count,
                peakWeight: peak,
                firstWeight: first,
                lastWeight: last,
                entries: sorted
            )
        }
    }

    static func programColor(hexByName: [String: String], program: String) -> String {
        hexByName[program] ?? (program == "User Logged" ? "#66bfcc" : "#888888")
    }
}
