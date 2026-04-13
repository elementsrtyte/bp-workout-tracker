import SwiftData
import SwiftUI

@main
struct bp_workoutApp: App {
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            AuthRootView()
                .environmentObject(appSettings)
                .environmentObject(UserProgramLibrary.shared)
                .onOpenURL { url in
                    Task { await SupabaseSessionManager.shared.handleAuthRedirect(url) }
                }
        }
        .modelContainer(for: [LoggedWorkout.self, LoggedExercise.self, LoggedSet.self])
    }
}
