import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]
    @ObservedObject private var bundle = BundleDataStore.shared
    @EnvironmentObject private var programLibrary: UserProgramLibrary

    var body: some View {
        TabView {
            NavigationStack {
                WorkoutHubView()
            }
            .tint(BlueprintTheme.purple)
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
        .task {
            await SupabaseSessionManager.shared.ensureSession()
            await bundle.refreshCatalogFromServer()
        }
        .onAppear {
            bundle.loadIfNeeded()
            bundle.setLoggedWorkoutsForBundledProgramUpdateScan(loggedWorkouts)
            bundle.refreshBundledProgramUpdateOffers(programLibrary: programLibrary)
        }
        .onChange(of: loggedWorkouts.count) { _, _ in
            bundle.setLoggedWorkoutsForBundledProgramUpdateScan(loggedWorkouts)
            bundle.refreshBundledProgramUpdateOffers(programLibrary: programLibrary)
        }
        .onChange(of: programLibrary.updateCounter) { _, _ in
            bundle.refreshBundledProgramUpdateOffers(programLibrary: programLibrary)
        }
        .onChange(of: bundle.userProgramsRevision) { _, _ in
            bundle.refreshBundledProgramUpdateOffers(programLibrary: programLibrary)
        }
        .alert(
            "Program updated",
            isPresented: Binding(
                get: { bundle.pendingBundledProgramUpdate != nil },
                set: { _ in }
            )
        ) {
            Button("Use latest") {
                bundle.resolveBundledProgramUpdateUseLatest()
            }
            Button("Keep my version") {
                bundle.resolveBundledProgramUpdateKeepCurrent()
            }
        } message: {
            if let o = bundle.pendingBundledProgramUpdate {
                Text("\(o.programName) was updated in the Blueprint library. Keep the version you’ve been using, or switch to the latest?")
            }
        }
    }
}
