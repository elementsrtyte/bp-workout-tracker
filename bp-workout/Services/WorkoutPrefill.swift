import Foundation

enum WorkoutPrefill {
    struct Suggestion: Equatable {
        var weight: Double
        var reps: Int
        /// Short label for PR / target context (e.g. "Peak 160 lb × 8").
        var prHint: String?
        /// Shown as "Plan:" on the workout card — peak load, or a 5–10% bump if no weight PR in ~3 weeks.
        var planDisplay: String
    }

    /// Days without a new weight PR before we suggest a heavier target.
    private static let prStaleCalendarDays = 21

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
        progressBundle: ProgressDataBundle?,
        prescriptionIsAmrap: Bool = false,
        prescriptionIsWarmup: Bool = false
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

        let planDisplayRaw = planDisplayLine(
            exerciseName: exerciseName,
            templateMax: templateMax,
            progress: progress
        )
        let planDisplay = planDisplayWithPrescriptionSuffixes(
            planDisplayRaw,
            amrap: prescriptionIsAmrap,
            warmup: prescriptionIsWarmup
        )

        if let last = lastSessionSet(for: key, workouts: loggedWorkouts) {
            return Suggestion(weight: last.weight, reps: last.reps, prHint: prHint, planDisplay: planDisplay)
        }
        if let p = progress, let last = p.entries.last {
            let w: Double
            if p.peakWeight > 0, isWeightPRStale(p) {
                w = bumpedTargetWeight(peak: p.peakWeight, exerciseName: exerciseName)
            } else {
                w = last.weight
            }
            return Suggestion(weight: w, reps: last.reps, prHint: prHint, planDisplay: planDisplay)
        }
        let tpl = parseTemplate(templateMax)
        var w = tpl.weight
        var r = tpl.reps
        if let p = progress, p.peakWeight > 0, isWeightPRStale(p) {
            w = bumpedTargetWeight(peak: p.peakWeight, exerciseName: exerciseName)
            if let peakR = repsAtPeakWeight(p), peakR > 0 {
                r = peakR
            }
        }
        return Suggestion(weight: w, reps: r, prHint: prHint, planDisplay: planDisplay)
    }

    private static func planDisplayWithPrescriptionSuffixes(_ base: String, amrap: Bool, warmup: Bool) -> String {
        var s = base
        if amrap {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { s = "AMRAP" } else { s = "\(s) · AMRAP" }
        }
        if warmup {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { s = "Warm-up" } else { s = "\(s) · Warm-up" }
        }
        return s
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

    // MARK: - Plan line (peak + progressive overload)

    private static let progressDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Stable 5%…10% bump per exercise name so the target doesn’t flicker between sessions.
    private static func progressiveBumpFraction(for exerciseName: String) -> Double {
        var hasher = Hasher()
        hasher.combine(exerciseName)
        let h = hasher.finalize()
        let u = Double(h % 10_000) / 10_000.0
        return 0.05 + 0.05 * u
    }

    private static func isWeightPRStale(_ progress: ExerciseProgress) -> Bool {
        guard progress.peakWeight > 0 else { return false }
        let chronological = progress.entries.sorted { $0.date < $1.date }
        guard let lastPRDay = lastWeightPRDate(from: chronological) else { return true }
        return calendarDaysSince(lastPRDay) >= prStaleCalendarDays
    }

    /// Heavier target after `peak * (5–10%)`, rounded to 2.5 lb, always above `peak`.
    private static func bumpedTargetWeight(peak: Double, exerciseName: String) -> Double {
        let frac = progressiveBumpFraction(for: exerciseName)
        var target = peak * (1 + frac)
        target = roundToPlateIncrement(target)
        if target <= peak {
            target = roundToPlateIncrement(peak * 1.05)
        }
        if target <= peak {
            target = peak + 2.5
        }
        return target
    }

    private static func parseProgressDay(_ dateString: String) -> Date? {
        progressDayFormatter.date(from: dateString)
    }

    private static func calendarDaysSince(_ start: Date, end: Date = .now) -> Int {
        let cal = Calendar.current
        let s = cal.startOfDay(for: start)
        let e = cal.startOfDay(for: end)
        return cal.dateComponents([.day], from: s, to: e).day ?? 0
    }

    /// Most recent date the running max **weight** increased (true PR progression in load).
    private static func lastWeightPRDate(from entriesChronological: [ProgressEntry]) -> Date? {
        var running = -Double.infinity
        var lastBump: Date?
        for e in entriesChronological {
            if e.weight > running + 0.01 {
                running = e.weight
                if let d = parseProgressDay(e.date) {
                    lastBump = d
                }
            }
        }
        return lastBump
    }

    private static func roundToPlateIncrement(_ w: Double) -> Double {
        guard w > 0 else { return 0 }
        let step = 2.5
        let r = (w / step).rounded() * step
        return max(step, r)
    }

    private static func planDisplayLine(
        exerciseName: String,
        templateMax: String,
        progress: ExerciseProgress?
    ) -> String {
        guard let p = progress, !p.entries.isEmpty, p.peakWeight > 0 else {
            let tpl = parseTemplate(templateMax)
            if tpl.weight > 0 {
                return "\(formatWeight(tpl.weight)) lb (program)"
            }
            return "BW · add reps, time, or load"
        }

        if !isWeightPRStale(p) {
            return "\(formatWeight(p.peakWeight)) lb"
        }
        let target = bumpedTargetWeight(peak: p.peakWeight, exerciseName: exerciseName)
        return "\(formatWeight(target)) lb · go for a new PR"
    }
}
