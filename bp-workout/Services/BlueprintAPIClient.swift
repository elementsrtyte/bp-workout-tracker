import Foundation

enum BlueprintAPIError: LocalizedError {
    case notConfigured
    case invalidURL
    case unauthorized
    case http(Int)
    case decode

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Blueprint API URL is not configured (BLUEPRINT_API_URL)."
        case .invalidURL: return "Invalid Blueprint API URL."
        case .unauthorized: return "Sign in again to use AI features."
        case .http(let c): return "Server request failed (\(c))."
        case .decode: return "Could not read server response."
        }
    }
}

enum BlueprintAPIClient {
    /// Public catalog and other unauthenticated routes.
    static func get(path: String) async throws -> Data {
        guard let base = BlueprintAPIConfig.baseURL else { throw BlueprintAPIError.notConfigured }
        var baseStr = base.absoluteString
        if baseStr.hasSuffix("/") { baseStr.removeLast() }
        let p = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: baseStr + p) else { throw BlueprintAPIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw BlueprintAPIError.http(-1) }
        guard (200 ... 299).contains(http.statusCode) else { throw BlueprintAPIError.http(http.statusCode) }
        return data
    }

    static func post<B: Encodable>(path: String, body: B, accessToken: String) async throws -> Data {
        guard let base = BlueprintAPIConfig.baseURL else { throw BlueprintAPIError.notConfigured }
        var baseStr = base.absoluteString
        if baseStr.hasSuffix("/") { baseStr.removeLast() }
        let p = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: baseStr + p) else { throw BlueprintAPIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw BlueprintAPIError.http(-1) }
        if http.statusCode == 401 { throw BlueprintAPIError.unauthorized }
        guard (200 ... 299).contains(http.statusCode) else { throw BlueprintAPIError.http(http.statusCode) }
        return data
    }

    /// POST with UTF-8 plain body (e.g. `/v1/ai/import-program/raw`).
    static func postPlainText(path: String, text: String, accessToken: String) async throws -> Data {
        guard let base = BlueprintAPIConfig.baseURL else { throw BlueprintAPIError.notConfigured }
        var baseStr = base.absoluteString
        if baseStr.hasSuffix("/") { baseStr.removeLast() }
        let p = path.hasPrefix("/") ? path : "/\(path)"
        guard let url = URL(string: baseStr + p) else { throw BlueprintAPIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data(text.utf8)

        let (data, res) = try await URLSession.shared.data(for: req)
        guard let http = res as? HTTPURLResponse else { throw BlueprintAPIError.http(-1) }
        if http.statusCode == 401 { throw BlueprintAPIError.unauthorized }
        guard (200 ... 299).contains(http.statusCode) else { throw BlueprintAPIError.http(http.statusCode) }
        return data
    }
}
