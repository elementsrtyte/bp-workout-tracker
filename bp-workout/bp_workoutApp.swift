import SwiftData
import SwiftUI

@main
struct bp_workoutApp: App {
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appSettings)
        }
        .modelContainer(for: [LoggedWorkout.self, LoggedExercise.self, LoggedSet.self])
    }
}
