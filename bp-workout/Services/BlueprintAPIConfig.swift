import Foundation

/// Base URL for the Blueprint API (AI and other server-side features).
enum BlueprintAPIConfig {
    static var baseURL: URL? {
        if let s = Bundle.main.object(forInfoDictionaryKey: "BLUEPRINT_API_URL") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = URL(string: t), !t.isEmpty { return u }
        }
        if let s = ProcessInfo.processInfo.environment["BLUEPRINT_API_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let u = URL(string: s), !s.isEmpty {
            return u
        }
        return nil
    }

    static var isConfigured: Bool {
        baseURL != nil
    }
}
