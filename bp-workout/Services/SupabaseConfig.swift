import Foundation

/// Auth endpoints on the Blueprint API (`/v1/auth/*`). Replaces Supabase GoTrue.
enum SupabaseConfig {
    /// Auth API base, e.g. `https://api.example.com/v1/auth`
    static var authBaseURL: URL? {
        guard let root = BlueprintAPIConfig.baseURL else { return nil }
        return root.appendingPathComponent("v1/auth", isDirectory: false)
    }

    static var isConfigured: Bool {
        BlueprintAPIConfig.isConfigured
    }
}
