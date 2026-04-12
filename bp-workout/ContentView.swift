import SwiftData
import SwiftUI

/// Legacy entry; app uses `RootView` from `bp_workoutApp`.
struct ContentView: View {
    var body: some View {
        RootView()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .modelContainer(for: [LoggedWorkout.self, LoggedExercise.self, LoggedSet.self], inMemory: true)
}
