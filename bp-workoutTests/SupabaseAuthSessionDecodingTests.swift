import XCTest
@testable import bp_workout

final class SupabaseAuthSessionDecodingTests: XCTestCase {
    private let sampleUserId = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

    func testDecodeFlatGoTruePayload() throws {
        let data = try jsonData([
            "access_token": "at",
            "refresh_token": "rt",
            "expires_in": 3600,
            "user": ["id": sampleUserId.uuidString],
        ])
        let s = try SupabaseAuthSessionDecoding.decodeSession(data)
        XCTAssertEqual(s.accessToken, "at")
        XCTAssertEqual(s.refreshToken, "rt")
        XCTAssertEqual(s.expiresIn, 3600)
        XCTAssertEqual(s.user?.id, sampleUserId)
        XCTAssertNil(s.user?.email)
    }

    func testDecodeUserEmail() throws {
        let data = try jsonData([
            "access_token": "at",
            "expires_in": 3600,
            "user": ["id": sampleUserId.uuidString, "email": "you@example.com"],
        ])
        let s = try SupabaseAuthSessionDecoding.decodeSession(data)
        XCTAssertEqual(s.user?.email, "you@example.com")
    }

    func testDecodeNestedSessionObject() throws {
        let data = try jsonData([
            "session": [
                "access_token": "nested-at",
                "refresh_token": "nested-rt",
                "expires_in": 1800,
                "user": ["id": sampleUserId.uuidString],
            ] as [String: Any],
        ])
        let s = try SupabaseAuthSessionDecoding.decodeSession(data)
        XCTAssertEqual(s.accessToken, "nested-at")
        XCTAssertEqual(s.refreshToken, "nested-rt")
        XCTAssertEqual(s.expiresIn, 1800)
        XCTAssertEqual(s.user?.id, sampleUserId)
    }

    func testDecodeExpiresAtWhenExpiresInMissing() throws {
        let now = Int(Date().timeIntervalSince1970)
        let expiresAt = now + 7200
        let data = try jsonData([
            "access_token": "at",
            "expires_at": expiresAt,
            "user": ["id": sampleUserId.uuidString],
        ])
        let s = try SupabaseAuthSessionDecoding.decodeSession(data)
        XCTAssertGreaterThanOrEqual(s.expiresIn, 7195)
        XCTAssertLessThanOrEqual(s.expiresIn, 7205)
    }

    func testDecodeUserIdFromString() throws {
        let data = try jsonData([
            "access_token": "at",
            "expires_in": 60,
            "user": ["id": sampleUserId.uuidString],
        ])
        let s = try SupabaseAuthSessionDecoding.decodeSession(data)
        XCTAssertEqual(s.user?.id, sampleUserId)
    }

    func testDecodeExpiresInDoubleRounds() throws {
        let data = try jsonData([
            "access_token": "at",
            "expires_in": 3600.7,
            "user": ["id": sampleUserId.uuidString],
        ])
        let s = try SupabaseAuthSessionDecoding.decodeSession(data)
        XCTAssertEqual(s.expiresIn, 3601)
    }

    func testNormalizedSessionJSONDataUnwrapsNestedSession() throws {
        let inner: [String: Any] = [
            "access_token": "in",
            "expires_in": 120,
        ]
        let wrapped = try jsonData(["session": inner])
        let normalized = SupabaseAuthSessionDecoding.normalizedSessionJSONData(wrapped)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: normalized) as? [String: Any])
        XCTAssertEqual(obj["access_token"] as? String, "in")
        XCTAssertEqual(obj["expires_in"] as? Int, 120)
    }

    private func jsonData(_ obj: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: obj)
    }
}
