import SwiftData
import SwiftUI

@main
struct bp_workoutApp: App {
    @StateObject private var appSettings = AppSettings()

    init() {
        BlueprintUIKitAccents.apply()
    }

    var body: some Scene {
        WindowGroup {
            AuthRootView()
                .environmentObject(appSettings)
                .environmentObject(UserProgramLibrary.shared)
                .tint(BlueprintTheme.purple)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    Task { await SupabaseSessionManager.shared.handleAuthRedirect(url) }
                }
        }
        .modelContainer(for: [LoggedWorkout.self, LoggedExercise.self, LoggedSet.self])
    }
}
