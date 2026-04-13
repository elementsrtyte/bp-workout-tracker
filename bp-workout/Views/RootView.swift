import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WorkoutHubView()
            }
            .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }

            LogWorkoutListView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            ProgressTrackerView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(BlueprintTheme.purple)
    }
}
