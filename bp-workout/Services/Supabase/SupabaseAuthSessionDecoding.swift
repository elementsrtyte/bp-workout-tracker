import Foundation

/// GoTrue / Supabase Auth session JSON (`/token`, `/signup` when a session is returned).
/// Kept separate from `SupabaseSessionManager` so decoding can be covered by unit tests.
enum SupabaseAuthSessionDecoding {
    /// If the root JSON has a `session` object, decode that blob (some clients wrap tokens there).
    static func normalizedSessionJSONData(_ data: Data) -> Data {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return data
        }
        if let session = obj["session"] as? [String: Any],
           JSONSerialization.isValidJSONObject(session),
           let nested = try? JSONSerialization.data(withJSONObject: session) {
            return nested
        }
        return data
    }

    /// Decode a session payload. Do **not** use `JSONDecoder.convertFromSnakeCase` here:
    /// it rewrites JSON keys before `CodingKeys` matching and breaks `access_token`, etc.
    static func decodeSession(_ data: Data) throws -> AuthSessionDTO {
        let payload = normalizedSessionJSONData(data)
        let dec = JSONDecoder()
        return try dec.decode(AuthSessionDTO.self, from: payload)
    }
}

struct AuthSessionDTO: Decodable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let user: UserDTO?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)
        user = try c.decodeIfPresent(UserDTO.self, forKey: .user)

        if let e = try c.decodeIfPresent(Double.self, forKey: .expiresIn) {
            expiresIn = Int(e.rounded())
        } else if let e = try c.decodeIfPresent(Int.self, forKey: .expiresIn) {
            expiresIn = e
        } else if let at = try c.decodeIfPresent(Double.self, forKey: .expiresAt) {
            expiresIn = Self.expiresInFromUnixExpiry(Int(at.rounded()))
        } else if let at = try c.decodeIfPresent(Int.self, forKey: .expiresAt) {
            expiresIn = Self.expiresInFromUnixExpiry(at)
        } else {
            expiresIn = 3600
        }
    }

    private static func expiresInFromUnixExpiry(_ expiresAtUnix: Int) -> Int {
        let now = Int(Date().timeIntervalSince1970)
        return max(60, expiresAtUnix - now)
    }

    struct UserDTO: Decodable, Equatable {
        let id: UUID

        private enum CodingKeys: String, CodingKey {
            case id
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let u = try? c.decode(UUID.self, forKey: .id) {
                id = u
            } else if let s = try? c.decode(String.self, forKey: .id), let u = UUID(uuidString: s) {
                id = u
            } else {
                let ctx = DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "user.id must be a UUID string"
                )
                throw DecodingError.dataCorrupted(ctx)
            }
        }
    }
}
