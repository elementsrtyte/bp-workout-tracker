import ActivityKit
import Foundation

@MainActor
enum WorkoutRestLiveActivityManager {
    private static var activity: Activity<WorkoutRestAttributes>?

    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func start(
        programName: String,
        dayLabel: String,
        exerciseName: String,
        setNumber: Int,
        totalSets: Int,
        targetReps: Int,
        isAmrap: Bool,
        weightLabel: String,
        restSeconds: Int
    ) {
        guard restSeconds > 0 else { return }
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let end = Date().addingTimeInterval(TimeInterval(restSeconds))
        let attrs = WorkoutRestAttributes(dayLabel: dayLabel, programName: programName)
        let state = WorkoutRestAttributes.ContentState(
            restEnd: end,
            exerciseName: exerciseName,
            setNumber: setNumber,
            totalSets: totalSets,
            targetReps: targetReps,
            isAmrap: isAmrap,
            weightLabel: weightLabel,
            isOvertime: false,
            overtimeSeconds: 0
        )
        let content = ActivityContent(state: state, staleDate: end.addingTimeInterval(600))
        do {
            activity = try Activity.request(attributes: attrs, content: content, pushType: nil)
        } catch {
            #if DEBUG
            print("[WorkoutRestLiveActivity] start failed: \(error.localizedDescription)")
            #endif
        }
    }

    static func updateOvertime(
        exerciseName: String,
        setNumber: Int,
        totalSets: Int,
        targetReps: Int,
        isAmrap: Bool,
        weightLabel: String,
        overtimeSeconds: Int
    ) {
        guard let activity else { return }
        let state = WorkoutRestAttributes.ContentState(
            restEnd: Date(),
            exerciseName: exerciseName,
            setNumber: setNumber,
            totalSets: totalSets,
            targetReps: targetReps,
            isAmrap: isAmrap,
            weightLabel: weightLabel,
            isOvertime: true,
            overtimeSeconds: overtimeSeconds
        )
        Task {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(3600)))
        }
    }

    static func end() {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
