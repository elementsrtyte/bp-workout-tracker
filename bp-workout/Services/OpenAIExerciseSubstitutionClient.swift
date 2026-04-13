import Foundation

/// Exercise swap suggestions via the Blueprint API (OpenAI runs server-side).
enum OpenAIExerciseSubstitutionClient {
    private struct SubstitutionRequest: Encodable {
        let prescribedExercise: String
        let userNote: String?
    }

    private struct SubstitutionResponse: Decodable {
        let suggestions: [String]
    }

    /// Returns a short list of exercise names; may be empty if the model reply is not valid JSON.
    static func fetchAlternatives(
        prescribedExercise: String,
        userNote: String?
    ) async throws -> [String] {
        let prescribed = prescribedExercise.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prescribed.isEmpty else { return [] }
        guard BlueprintAPIConfig.isConfigured else { throw BlueprintAPIError.notConfigured }
        let token = try await SupabaseSessionManager.shared.accessTokenForAPI()
        let trimmedNote = userNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = SubstitutionRequest(
            prescribedExercise: prescribed,
            userNote: (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        )
        let data = try await BlueprintAPIClient.post(
            path: "/v1/ai/substitution-suggestions",
            body: body,
            accessToken: token
        )
        let decoded = try JSONDecoder().decode(SubstitutionResponse.self, from: data)
        return decoded.suggestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
