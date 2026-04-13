import Foundation

/// Supabase project URL and anon key (GoTrue sign-in and token refresh).
enum SupabaseConfig {
    /// API root, e.g. `https://xyz.supabase.co` or `http://127.0.0.1:54321` (no trailing slash).
    static var apiRootURL: URL? {
        if let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let u = URL(string: t), !t.isEmpty { return u }
        }
        if let s = ProcessInfo.processInfo.environment["SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           let u = URL(string: s), !s.isEmpty {
            return u
        }
        return nil
    }

    static var anonKey: String? {
        if let s = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if let s = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            return s
        }
        return nil
    }

    static var isConfigured: Bool {
        apiRootURL != nil && anonKey != nil
    }
}
