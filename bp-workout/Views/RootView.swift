import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                WorkoutHubView()
            }
            .tabItem { Label("Workout", systemImage: "figure.strengthtraining.traditional") }

            ProgressTrackerView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            GymCalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }

            ProgramMarketplaceView()
                .tabItem { Label("Programs", systemImage: "storefront") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(BlueprintTheme.purple)
        .preferredColorScheme(.dark)
    }
}
