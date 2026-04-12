import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem { Label("Programs", systemImage: "list.bullet.rectangle") }

            LogWorkoutListView()
                .tabItem { Label("Log", systemImage: "plus.square.on.square") }

            ProgressTrackerView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(BlueprintTheme.purple)
    }
}
