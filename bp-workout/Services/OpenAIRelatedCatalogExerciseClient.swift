import Foundation

/// Picks related lifts from a fixed catalog via the Blueprint API (OpenAI runs server-side).
enum OpenAIRelatedCatalogExerciseClient {
    enum ClientError: LocalizedError {
        case emptyExerciseName
        case emptyAllowedList

        var errorDescription: String? {
            switch self {
            case .emptyExerciseName: return "Enter an exercise name first."
            case .emptyAllowedList: return "Exercise catalog is empty."
            }
        }
    }

    private struct RelatedRequest: Encodable {
        let exerciseName: String
        let allowedExactNames: [String]
        let limit: Int
    }

    private struct RelatedResponse: Decodable {
        let related: [String]
    }

    /// Returns up to `limit` names, each exactly matching an entry in `allowedExactNames` (case-insensitive).
    static func fetchRelated(
        exerciseName: String,
        allowedExactNames: [String],
        limit: Int = 12
    ) async throws -> [String] {
        let ex = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ex.isEmpty else { throw ClientError.emptyExerciseName }

        let allowed = Array(
            Set(
                allowedExactNames
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        guard !allowed.isEmpty else { throw ClientError.emptyAllowedList }

        guard BlueprintAPIConfig.isConfigured else { throw BlueprintAPIError.notConfigured }
        let token = try await SupabaseSessionManager.shared.accessTokenForAPI()
        let body = RelatedRequest(exerciseName: ex, allowedExactNames: allowed, limit: min(12, max(1, limit)))
        let data = try await BlueprintAPIClient.post(
            path: "/v1/exercises/related",
            body: body,
            accessToken: token
        )
        let decoded = try JSONDecoder().decode(RelatedResponse.self, from: data)
        return decoded.related
    }
}
