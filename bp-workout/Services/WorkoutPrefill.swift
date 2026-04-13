import Foundation

enum WorkoutPrefill {
    struct Suggestion: Equatable {
        var weight: Double
        var reps: Int
        /// Short label for PR / target context (e.g. "Peak 160 lb × 8").
        var prHint: String?
    }

    /// Best-effort parse of program template strings like "155 lbs", "Bodyweight", "60s hold".
    static func parseTemplate(_ raw: String) -> (weight: Double, reps: Int) {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.contains("hold") || lower.contains("sec") || lower.contains("s hold") {
            if let n = firstNumber(in: raw) {
                return (0, max(1, Int(n.rounded())))
            }
        }
        if lower.contains("bodyweight") || lower == "bw" {
            return (0, 8)
        }
        if let w = firstNumber(in: raw) {
            return (w, 8)
        }
        return (0, 8)
    }

    static func suggest(
        exerciseName: String,
        templateMax: String,
        loggedWorkouts: [LoggedWorkout],
        progressBundle: ProgressDataBundle?
    ) -> Suggestion {
        let key = ExerciseNameNormalizer.key(exerciseName)
        let userEntries = LoggedWorkoutProgressExport.entriesByExerciseName(workouts: loggedWorkouts)
        let merged: [ExerciseProgress] = {
            guard let b = progressBundle else {
                return userEntries.map { pair in
                    let name = pair.key
                    let entries = pair.value
                    let sorted = entries.sorted { $0.date < $1.date }
                    let w = sorted.map(\.weight)
                    return ExerciseProgress(
                        name: name,
                        sessionCount: sorted.count,
                        peakWeight: w.max() ?? 0,
                        firstWeight: sorted.first?.weight ?? 0,
                        lastWeight: sorted.last?.weight ?? 0,
                        entries: sorted
                    )
                }
            }
            return ProgressMergeService.mergedExerciseProgress(bundle: b, userEntriesByExercise: userEntries)
        }()

        let progress = merged.first { ExerciseNameNormalizer.key($0.name) == key }
        let prHint: String? = {
            guard let p = progress, p.peakWeight > 0 else {
                let tpl = parseTemplate(templateMax)
                if tpl.weight > 0 { return "Target \(formatWeight(tpl.weight)) lb" }
                if tpl.reps > 0, tpl.weight == 0 { return "Hold / BW" }
                return nil
            }
            let peakReps = repsAtPeakWeight(p)
            if let r = peakReps, r > 0 {
                return "Peak \(formatWeight(p.peakWeight)) lb × \(r)"
            }
            return "Peak \(formatWeight(p.peakWeight)) lb"
        }()

        if let last = lastSessionSet(for: key, workouts: loggedWorkouts) {
            return Suggestion(weight: last.weight, reps: last.reps, prHint: prHint)
        }
        if let p = progress, let last = p.entries.last {
            return Suggestion(weight: last.weight, reps: last.reps, prHint: prHint)
        }
        let tpl = parseTemplate(templateMax)
        return Suggestion(weight: tpl.weight, reps: tpl.reps, prHint: prHint)
    }

    static func formatWeight(_ w: Double) -> String {
        if w == floor(w) { return String(Int(w)) }
        return w.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func lastSessionSet(for key: String, workouts: [LoggedWorkout]) -> (weight: Double, reps: Int)? {
        let sorted = workouts.sorted { $0.date > $1.date }
        for w in sorted {
            for ex in w.exercises.sorted(by: { $0.sortOrder < $1.sortOrder }) {
                guard ExerciseNameNormalizer.key(ex.name) == key else { continue }
                let sets = ex.sets.sorted { $0.order < $1.order }
                guard let last = sets.last else { continue }
                return (last.weight, last.reps)
            }
        }
        return nil
    }

    private static func firstNumber(in raw: String) -> Double? {
        let pattern = #"[0-9]+(?:\.[0-9]+)?"#
        guard let range = raw.range(of: pattern, options: .regularExpression) else { return nil }
        return Double(raw[range])
    }

    /// Best rep count achieved at the exercise’s peak load (handles multiple sets at the same weight).
    private static func repsAtPeakWeight(_ p: ExerciseProgress) -> Int? {
        guard p.peakWeight > 0 else { return nil }
        let peak = p.peakWeight
        let atPeak = p.entries.filter { abs($0.weight - peak) < 0.01 }
        guard !atPeak.isEmpty else { return nil }
        return atPeak.map(\.reps).max()
    }
}
