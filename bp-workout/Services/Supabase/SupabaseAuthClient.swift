import Combine
import Foundation

/// Supabase Auth: email/password sign-in, password recovery via `bpworkout://auth`, session in Keychain.
@MainActor
final class SupabaseSessionManager: ObservableObject {
    static let shared = SupabaseSessionManager()

    /// UserDefaults key for login email prefill (not the legacy device-scoped email).
    static let savedEmailKey = "supabase.saved.email"

    /// Must match `additional_redirect_urls` in `supabase/config.toml` and the app URL scheme.
    static let authRedirectURL = URL(string: "bpworkout://auth")!

    enum AuthPhase: Equatable {
        case checking
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: AuthPhase = .checking
    /// After opening a recovery deep link, user must set a new password before using the app.
    @Published private(set) var awaitingPasswordResetCompletion = false

    private let legacyDeviceEmailKey = "supabase.device.email"
    private let kRefresh = "refresh_token"
    private let kPassword = "device_password"

    private var accessToken: String?
    private var accessExpires: Date?
    private(set) var userId: UUID?

    private init() {}

    // MARK: - Bootstrap & session

    func bootstrap() async {
        phase = .checking
        awaitingPasswordResetCompletion = false
        guard SupabaseConfig.isConfigured else {
            phase = .signedOut
            return
        }
        guard let refreshData = KeychainStore.get(account: kRefresh),
              let refresh = String(data: refreshData, encoding: .utf8), !refresh.isEmpty
        else {
            phase = .signedOut
            return
        }
        guard let root = SupabaseConfig.apiRootURL, let anon = SupabaseConfig.anonKey else {
            phase = .signedOut
            return
        }
        let authBase = root.appendingPathComponent("auth/v1", isDirectory: false)
        do {
            let s = try await postTokenExchange(
                authBase: authBase,
                anonKey: anon,
                grantType: "refresh_token",
                body: ["refresh_token": refresh]
            )
            applySession(s)
            phase = .signedIn
        } catch {
            if shouldInvalidateRefreshStorage(for: error) {
                KeychainStore.remove(account: kRefresh)
            }
            phase = .signedOut
        }
    }

    /// Ensures a valid access token when already signed in (e.g. before catalog sync).
    func ensureSession() async {
        guard SupabaseConfig.isConfigured, phase == .signedIn else { return }
        do {
            try await refreshSessionIfNeeded()
        } catch {
            // Offline or expired; callers retry on next save / foreground.
        }
    }

    func accessTokenForAPI() async throws -> String {
        guard SupabaseConfig.isConfigured else {
            throw SupabaseAuthError.notConfigured
        }
        guard phase == .signedIn else { throw SupabaseAuthError.noSession }
        try await refreshSessionIfNeeded()
        guard let t = accessToken, !t.isEmpty else {
            throw SupabaseAuthError.noSession
        }
        return t
    }

    func userIdForAPI() throws -> UUID {
        guard let id = userId else { throw SupabaseAuthError.noSession }
        return id
    }

    func signOut() {
        KeychainStore.remove(account: kRefresh)
        KeychainStore.remove(account: kPassword)
        UserDefaults.standard.removeObject(forKey: legacyDeviceEmailKey)
        accessToken = nil
        accessExpires = nil
        userId = nil
        awaitingPasswordResetCompletion = false
        phase = .signedOut
    }

    // MARK: - Email / password

    func signIn(email: String, password: String) async throws {
        guard let root = SupabaseConfig.apiRootURL, let anon = SupabaseConfig.anonKey else {
            throw SupabaseAuthError.notConfigured
        }
        let authBase = root.appendingPathComponent("auth/v1", isDirectory: false)
        let s = try await postPasswordSignIn(
            authBase: authBase,
            anonKey: anon,
            email: email,
            password: password
        )
        applySession(s)
        awaitingPasswordResetCompletion = false
        phase = .signedIn
    }

    func signUp(email: String, password: String) async throws {
        guard let root = SupabaseConfig.apiRootURL, let anon = SupabaseConfig.anonKey else {
            throw SupabaseAuthError.notConfigured
        }
        let authBase = root.appendingPathComponent("auth/v1", isDirectory: false)
        let s = try await postSignUp(authBase: authBase, anonKey: anon, email: email, password: password)
        applySession(s)
        awaitingPasswordResetCompletion = false
        phase = .signedIn
    }

    func requestPasswordReset(email: String) async throws {
        guard let root = SupabaseConfig.apiRootURL, let anon = SupabaseConfig.anonKey else {
            throw SupabaseAuthError.notConfigured
        }
        let authBase = root.appendingPathComponent("auth/v1", isDirectory: false)
        try await postRecover(
            authBase: authBase,
            anonKey: anon,
            email: email,
            redirectTo: Self.authRedirectURL.absoluteString
        )
    }

    /// Call after recovery deep link established a session (still on “set new password” screen).
    func completePasswordRecovery(newPassword: String) async throws {
        guard let root = SupabaseConfig.apiRootURL, let anon = SupabaseConfig.anonKey else {
            throw SupabaseAuthError.notConfigured
        }
        try await refreshSessionIfNeeded()
        guard let token = accessToken, !token.isEmpty else { throw SupabaseAuthError.noSession }
        let authBase = root.appendingPathComponent("auth/v1", isDirectory: false)
        try await patchUserPassword(authBase: authBase, anonKey: anon, accessToken: token, newPassword: newPassword)
        awaitingPasswordResetCompletion = false
    }

    // MARK: - Deep link (magic link / recovery)

    func handleAuthRedirect(_ url: URL) async {
        guard url.scheme?.lowercased() == "bpworkout", url.host?.lowercased() == "auth" else { return }
        guard let parsed = Self.parseAuthFragment(url) else { return }
        do {
            let dto = try sessionDTO(fromFragment: parsed)
            applySession(dto)
            let isRecovery = parsed.linkType?.lowercased() == "recovery"
            awaitingPasswordResetCompletion = isRecovery
            phase = .signedIn
        } catch {
            // Malformed fragment; ignore.
        }
    }

    // MARK: - Private

    private func refreshSessionIfNeeded() async throws {
        if accessToken != nil, let exp = accessExpires, exp > Date().addingTimeInterval(120) {
            return
        }
        guard let root = SupabaseConfig.apiRootURL, let anon = SupabaseConfig.anonKey else {
            throw SupabaseAuthError.notConfigured
        }
        guard let refreshData = KeychainStore.get(account: kRefresh),
              let refresh = String(data: refreshData, encoding: .utf8), !refresh.isEmpty
        else {
            throw SupabaseAuthError.noSession
        }
        let authBase = root.appendingPathComponent("auth/v1", isDirectory: false)
        let s = try await postTokenExchange(
            authBase: authBase,
            anonKey: anon,
            grantType: "refresh_token",
            body: ["refresh_token": refresh]
        )
        applySession(s)
    }

    private func applySession(_ s: AuthSessionDTO) {
        accessToken = s.accessToken
        accessExpires = Date().addingTimeInterval(TimeInterval(s.expiresIn - 60))
        userId = s.user?.id ?? Self.uuidFromJwtSub(s.accessToken)
        if let r = s.refreshToken, !r.isEmpty {
            KeychainStore.set(Data(r.utf8), account: kRefresh)
        }
    }

    private static func uuidFromJwtSub(_ jwt: String) -> UUID? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1])
        while b64.count % 4 != 0 { b64.append("=") }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = obj["sub"] as? String
        else { return nil }
        return UUID(uuidString: sub)
    }

    private struct ParsedFragment {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        let linkType: String?
    }

    private func sessionDTO(fromFragment parsed: ParsedFragment) throws -> AuthSessionDTO {
        var dict: [String: Any] = [
            "access_token": parsed.accessToken,
            "expires_in": parsed.expiresIn,
        ]
        if let r = parsed.refreshToken { dict["refresh_token"] = r }
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try decodeSession(data)
    }

    private static func parseAuthFragment(_ url: URL) -> ParsedFragment? {
        guard let fragment = url.fragment, !fragment.isEmpty else { return nil }
        var dict: [String: String] = [:]
        for pair in fragment.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let key = parts[0].removingPercentEncoding ?? parts[0]
            let value = parts[1].removingPercentEncoding ?? parts[1]
            dict[key] = value
        }
        guard let access = dict["access_token"], !access.isEmpty else { return nil }
        let refresh = dict["refresh_token"].flatMap { $0.isEmpty ? nil : $0 }
        let exp = dict["expires_in"].flatMap { Int($0) } ?? 3600
        let type = dict["type"]
        return ParsedFragment(accessToken: access, refreshToken: refresh, expiresIn: exp, linkType: type)
    }

    private func postSignUp(authBase: URL, anonKey: String, email: String, password: String) async throws -> AuthSessionDTO {
        let url = authBase.appendingPathComponent("signup")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["email": email, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, res) = try await URLSession.shared.data(for: req)
        try throwIfBadHTTP(res, data: data)
        return try decodeSessionOrSignupMessage(data)
    }

    private func postPasswordSignIn(authBase: URL, anonKey: String, email: String, password: String) async throws -> AuthSessionDTO {
        try await postTokenExchange(
            authBase: authBase,
            anonKey: anonKey,
            grantType: "password",
            body: ["email": email, "password": password]
        )
    }

    private func postRecover(authBase: URL, anonKey: String, email: String, redirectTo: String) async throws {
        let url = authBase.appendingPathComponent("recover")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["email": email, "redirect_to": redirectTo]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, res) = try await URLSession.shared.data(for: req)
        try throwIfBadHTTP(res, data: data)
    }

    private func patchUserPassword(authBase: URL, anonKey: String, accessToken: String, newPassword: String) async throws {
        let url = authBase.appendingPathComponent("user")
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = ["password": newPassword]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, res) = try await URLSession.shared.data(for: req)
        try throwIfBadHTTP(res, data: data)
    }

    private func postTokenExchange(
        authBase: URL,
        anonKey: String,
        grantType: String,
        body: [String: Any]
    ) async throws -> AuthSessionDTO {
        var components = URLComponents(
            url: authBase.appendingPathComponent("token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        guard let url = components?.url else { throw SupabaseAuthError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, res) = try await URLSession.shared.data(for: req)
        try throwIfBadHTTP(res, data: data)
        return try decodeSession(data)
    }

    private func throwIfBadHTTP(_ res: URLResponse, data: Data) throws {
        guard let http = res as? HTTPURLResponse else { throw SupabaseAuthError.http(-1) }
        guard (200 ... 299).contains(http.statusCode) else {
            throw SupabaseAuthError.fromResponse(status: http.statusCode, data: data)
        }
    }

    private func decodeSession(_ data: Data) throws -> AuthSessionDTO {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(AuthSessionDTO.self, from: data)
    }

    /// Sign-up may return a user without a session when email confirmation is required.
    private func decodeSessionOrSignupMessage(_ data: Data) throws -> AuthSessionDTO {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let at = obj["access_token"] as? String, !at.isEmpty {
                return try decodeSession(data)
            }
            if obj["user"] != nil {
                let msg = (obj["msg"] as? String)
                    ?? "Check your email to confirm your account, then sign in."
                throw SupabaseAuthError.server(msg)
            }
        }
        return try decodeSession(data)
    }

    private func shouldInvalidateRefreshStorage(for error: Error) -> Bool {
        if case SupabaseAuthError.http(let code) = error, code == 401 || code == 400 {
            return true
        }
        if case SupabaseAuthError.server(let msg) = error {
            let m = msg.lowercased()
            if m.contains("invalid_grant") || m.contains("invalid refresh") || m.contains("jwt") {
                return true
            }
        }
        return false
    }
}

enum SupabaseAuthError: LocalizedError {
    case notConfigured
    case badURL
    case http(Int)
    case decode
    case noSession
    case server(String)

    static func fromResponse(status: Int, data: Data) -> SupabaseAuthError {
        if let msg = parseGoTrueErrorMessage(data) {
            return .server(msg)
        }
        return .http(status)
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Supabase is not configured."
        case .badURL: return "Invalid auth URL."
        case .http(let c): return "Auth request failed (\(c))."
        case .decode: return "Could not read auth response."
        case .noSession: return "No Supabase session."
        case .server(let s): return s
        }
    }
}

private func parseGoTrueErrorMessage(_ data: Data) -> String? {
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    if let d = obj["error_description"] as? String, !d.isEmpty { return d }
    if let d = obj["msg"] as? String, !d.isEmpty { return d }
    if let d = obj["message"] as? String, !d.isEmpty { return d }
    if let e = obj["error"] as? String, !e.isEmpty {
        if e == "invalid_grant" { return "Invalid email or password." }
        return e.replacingOccurrences(of: "_", with: " ").capitalized
    }
    return nil
}

private struct AuthSessionDTO: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let user: UserDTO?

    struct UserDTO: Decodable {
        let id: UUID
    }
}
