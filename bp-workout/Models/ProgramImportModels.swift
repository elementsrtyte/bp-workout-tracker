import Foundation
import SwiftData

/// What the user indicated they are importing (drives API prompt and post-parse routing).
enum ProgramImportContentKind: String, CaseIterable, Identifiable {
    case newProgram
    case workoutLog
    case newTrainingDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newProgram: return "New program"
        case .workoutLog: return "Past workouts (log)"
        case .newTrainingDay: return "New day in existing program"
        }
    }

    var detail: String {
        switch self {
        case .newProgram:
            return "Template and optional history from one paste. Opens the program editor."
        case .workoutLog:
            return "Completed sessions (sets/reps/weights). Dates in the text help; if missing, the app picks placeholder days. Choose which program these logs belong to."
        case .newTrainingDay:
            return "One training day to add to a program you already have. Choose the program, then paste that day’s exercises."
        }
    }

    var apiImportKind: String {
        switch self {
        case .newProgram: return "program"
        case .workoutLog: return "workout_log"
        case .newTrainingDay: return "program_day"
        }
    }
}

/// Full result of a text/file program import (template + optional logged history).
struct ProgramImportResult: Sendable {
    let program: WorkoutProgram
    let historicalWorkouts: [HistoricalWorkoutDraft]
}

/// Callback bundle: import kind, optional target program, and parsed payload.
struct ProgramImportOutcome: Sendable {
    let contentKind: ProgramImportContentKind
    /// Profile program when `.workoutLog` or `.newTrainingDay` requires a selection.
    let selectedProgram: WorkoutProgram?
    let result: ProgramImportResult
}

enum ProgramImportMerge {
    /// Appends the first imported day to `base`, fixing label collisions.
    static func appendingFirstDay(base: WorkoutProgram, imported: WorkoutProgram) -> WorkoutProgram? {
        guard let day = imported.days.first else { return nil }
        var used = Set(base.days.map(\.label))
        let rawLabel = day.label.trimmingCharacters(in: .whitespacesAndNewlines)
        var label = rawLabel.isEmpty ? "Imported day" : rawLabel
        if used.contains(label) {
            var n = 1
            var candidate = "\(label) (imported)"
            while used.contains(candidate) {
                n += 1
                candidate = "\(label) (imported \(n))"
            }
            label = candidate
        }
        let newDay = WorkoutDay(label: label, exercises: day.exercises)
        return WorkoutProgram(
            id: base.id,
            name: base.name,
            subtitle: base.subtitle,
            period: base.period,
            dateRange: base.dateRange,
            days: base.days + [newDay],
            color: base.color,
            isUserCreated: base.isUserCreated,
            categorySlug: base.categorySlug,
            categoryTitle: base.categoryTitle
        )
    }

    /// Compact summary of days for the LLM (program_day mode).
    static func summarizeDaysForAPI(_ program: WorkoutProgram) -> String {
        program.days.map { day in
            let names = day.exercises.map(\.name).joined(separator: ", ")
            return "- \(day.label): \(names)"
        }.joined(separator: "\n")
    }
}

struct HistoricalWorkoutDraft: Sendable {
    let date: Date
    let dayLabel: String?
    let notes: String?
    let exercises: [HistoricalExerciseDraft]
}

struct HistoricalExerciseDraft: Sendable {
    let name: String
    let prescribedName: String?
    let sets: [HistoricalSetDraft]
}

struct HistoricalSetDraft: Sendable {
    let weight: Double
    let reps: Int
}

@MainActor
enum ImportHistoryPersistence {
    /// Inserts imported historical sessions and returns them for optional Supabase push.
    static func apply(
        _ drafts: [HistoricalWorkoutDraft],
        programId: String,
        programName: String,
        modelContext: ModelContext
    ) throws -> [LoggedWorkout] {
        var inserted: [LoggedWorkout] = []
        for d in drafts {
            let workout = LoggedWorkout(
                date: d.date,
                programId: programId,
                programName: programName,
                dayLabel: d.dayLabel,
                notes: d.notes
            )
            for (i, exDraft) in d.exercises.enumerated() {
                let ex = LoggedExercise(
                    name: exDraft.name,
                    prescribedName: exDraft.prescribedName,
                    sortOrder: i
                )
                for (j, sDraft) in exDraft.sets.enumerated() {
                    ex.sets.append(
                        LoggedSet(weight: sDraft.weight, reps: sDraft.reps, order: j)
                    )
                }
                workout.exercises.append(ex)
            }
            modelContext.insert(workout)
            inserted.append(workout)
        }
        if !inserted.isEmpty {
            try modelContext.save()
        }
        return inserted
    }
}
