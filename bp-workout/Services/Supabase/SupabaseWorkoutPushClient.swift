import Foundation

/// Pushes a locally saved `LoggedWorkout` tree via the Blueprint API (server writes to Supabase).
enum BlueprintWorkoutSyncClient {
    private struct SyncSet: Encodable {
        let id: UUID
        let weight: Double
        let reps: Int
        let order: Int
    }

    private struct SyncExercise: Encodable {
        let id: UUID
        let name: String
        let prescribedName: String?
        let sortOrder: Int
        let sets: [SyncSet]
    }

    private struct SyncBody: Encodable {
        let id: UUID
        let date: String
        let programId: String?
        let programName: String?
        let dayLabel: String?
        let notes: String?
        let exercises: [SyncExercise]
    }

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    @MainActor
    static func push(_ workout: LoggedWorkout) async {
        guard BlueprintAPIConfig.isConfigured else { return }
        let token: String
        do {
            token = try await SupabaseSessionManager.shared.accessTokenForAPI()
        } catch {
            return
        }

        let sortedEx = workout.exercises.sorted { $0.sortOrder < $1.sortOrder }
        let syncEx: [SyncExercise] = sortedEx.map { ex in
            let sortedSets = ex.sets.sorted { $0.order < $1.order }
            return SyncExercise(
                id: ex.id,
                name: ex.name,
                prescribedName: ex.prescribedName,
                sortOrder: ex.sortOrder,
                sets: sortedSets.map { SyncSet(id: $0.id, weight: $0.weight, reps: $0.reps, order: $0.order) }
            )
        }

        let body = SyncBody(
            id: workout.id,
            date: iso8601.string(from: workout.date),
            programId: workout.programId,
            programName: workout.programName,
            dayLabel: workout.dayLabel,
            notes: workout.notes,
            exercises: syncEx
        )

        do {
            _ = try await BlueprintAPIClient.post(path: "/v1/sync/workout", body: body, accessToken: token)
        } catch {
            // Non-fatal: local SwiftData row remains source of truth until sync succeeds.
        }
    }
}
