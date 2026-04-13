import Foundation

/// Weekly streak: consecutive calendar weeks where the user hits their program’s session target.
enum WorkoutWeeklyStreakEngine {

    struct Snapshot: Equatable {
        /// Sessions required each week (from program rotation length, else 3).
        let requiredSessionsPerWeek: Int
        /// Program whose name we filter logged workouts on; nil = all workouts.
        let programFilterName: String?

        /// Saved sessions in the current calendar week (matching filter).
        let currentWeekSessions: Int
        /// Consecutive weeks ending with the current chain rule (see engine).
        let currentStreakWeeks: Int
        /// Longest run of qualifying weeks in history (same rules).
        let bestStreakWeeks: Int
    }

    struct Medal: Identifiable, Equatable {
        let id: String
        let title: String
        let systemImage: String
        let weeksRequired: Int
    }

    /// Ordered from easiest to hardest; unlock when `bestStreakWeeks >= weeksRequired`.
    static let medals: [Medal] = [
        Medal(id: "spark", title: "First Spark", systemImage: "sparkles", weeksRequired: 2),
        Medal(id: "bronze", title: "Bronze Discipline", systemImage: "medal.fill", weeksRequired: 4),
        Medal(id: "silver", title: "Silver Drive", systemImage: "star.circle.fill", weeksRequired: 8),
        Medal(id: "gold", title: "Gold Standard", systemImage: "trophy.fill", weeksRequired: 12),
        Medal(id: "crown", title: "Blueprint Crown", systemImage: "crown.fill", weeksRequired: 20),
    ]

    static func requiredSessionsPerWeek(for program: WorkoutProgram?) -> Int {
        guard let p = program, !p.days.isEmpty else { return 3 }
        return max(1, min(7, p.days.count))
    }

    static func snapshot(
        loggedWorkouts: [LoggedWorkout],
        activeProgram: WorkoutProgram?,
        calendar: Calendar = .current,
        referenceDate: Date = .now
    ) -> Snapshot {
        let required = requiredSessionsPerWeek(for: activeProgram)
        let filterName = activeProgram?.name

        let week0 = calendar.startOfWeek(containing: referenceDate)
        let cur = sessionCount(
            weekStarting: week0,
            workouts: loggedWorkouts,
            programName: filterName,
            calendar: calendar
        )

        let streak = currentStreakWeeks(
            week0: week0,
            required: required,
            workouts: loggedWorkouts,
            programName: filterName,
            calendar: calendar
        )

        let best = bestStreakWeeks(
            required: required,
            workouts: loggedWorkouts,
            programName: filterName,
            calendar: calendar,
            referenceDate: referenceDate
        )

        return Snapshot(
            requiredSessionsPerWeek: required,
            programFilterName: filterName,
            currentWeekSessions: cur,
            currentStreakWeeks: streak,
            bestStreakWeeks: best
        )
    }

    // MARK: - Core counting

    private static func matchesProgram(_ workout: LoggedWorkout, programName: String?) -> Bool {
        guard let name = programName, !name.isEmpty else { return true }
        return workout.programName == name
    }

    private static func sessionCount(
        weekStarting weekStart: Date,
        workouts: [LoggedWorkout],
        programName: String?,
        calendar: Calendar
    ) -> Int {
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) else { return 0 }
        return workouts.reduce(into: 0) { count, w in
            guard w.date >= weekStart && w.date < weekEnd else { return }
            guard matchesProgram(w, programName: programName) else { return }
            count += 1
        }
    }

    /// Current streak: prior consecutive qualifying weeks, plus1 if this week already hit the target.
    private static func currentStreakWeeks(
        week0: Date,
        required: Int,
        workouts: [LoggedWorkout],
        programName: String?,
        calendar: Calendar
    ) -> Int {
        var streak = 0
        var week = week0

        let curCount = sessionCount(weekStarting: week, workouts: workouts, programName: programName, calendar: calendar)
        if curCount >= required { streak += 1 }

        guard let previousWeekStart = calendar.date(byAdding: .day, value: -7, to: week0) else { return streak }
        week = previousWeekStart

        while true {
            let c = sessionCount(weekStarting: week, workouts: workouts, programName: programName, calendar: calendar)
            if c >= required {
                streak += 1
            } else {
                break
            }
            guard let p = calendar.date(byAdding: .day, value: -7, to: week) else { break }
            week = p
        }

        return streak
    }

    private static func bestStreakWeeks(
        required: Int,
        workouts: [LoggedWorkout],
        programName: String?,
        calendar: Calendar,
        referenceDate: Date
    ) -> Int {
        let dates = workouts.filter { matchesProgram($0, programName: programName) }.map(\.date)
        guard let oldest = dates.min() else { return 0 }

        var week = calendar.startOfWeek(containing: oldest)
        let endWeek = calendar.startOfWeek(containing: referenceDate)

        var run = 0
        var best = 0

        while week <= endWeek {
            let c = sessionCount(weekStarting: week, workouts: workouts, programName: programName, calendar: calendar)
            if c >= required {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
            guard let next = calendar.date(byAdding: .day, value: 7, to: week) else { break }
            week = next
        }

        return best
    }
}

private extension Calendar {
    func startOfWeek(containing date: Date) -> Date {
        let c = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        guard let start = self.date(from: c) else { return startOfDay(for: date) }
        return startOfDay(for: start)
    }
}
