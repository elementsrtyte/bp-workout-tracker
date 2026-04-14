import Foundation

/// Loads the published workout catalog from the Blueprint API (server-side PostgREST).
enum BlueprintCatalogFetcher {
    enum FetchError: LocalizedError {
        case notConfigured
        case badStatus(Int)
        case decode(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Blueprint API URL is missing (BLUEPRINT_API_URL)."
            case .badStatus(let c): return "Catalog request failed (\(c))."
            case .decode(let m): return m
            }
        }
    }

    static func fetchWorkoutProgramsBundle() async throws -> WorkoutProgramsBundle {
        guard BlueprintAPIConfig.isConfigured else {
            throw FetchError.notConfigured
        }
        let data: Data
        do {
            data = try await BlueprintAPIClient.get(path: "/v1/catalog/programs")
        } catch let e as BlueprintAPIError {
            switch e {
            case .notConfigured: throw FetchError.notConfigured
            case .invalidURL: throw FetchError.decode("Invalid catalog URL")
            case .http(let c): throw FetchError.badStatus(c)
            case .unauthorized, .decode: throw FetchError.badStatus(-1)
            }
        }
        do {
            return try JSONDecoder().decode(WorkoutProgramsBundle.self, from: data)
        } catch {
            throw FetchError.decode(error.localizedDescription)
        }
    }
}
