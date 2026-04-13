import Foundation
import SwiftData

/// Full result of a text/file program import (template + optional logged history).
struct ProgramImportResult: Sendable {
    let program: WorkoutProgram
    let historicalWorkouts: [HistoricalWorkoutDraft]
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
