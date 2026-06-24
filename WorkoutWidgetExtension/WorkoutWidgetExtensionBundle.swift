import ActivityKit
import SwiftUI
import WidgetKit

@main
struct WorkoutWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        WorkoutRestLiveActivityWidget()
    }
}

struct WorkoutRestLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutRestAttributes.self) { context in
            WorkoutRestLockScreenView(state: context.state, attributes: context.attributes)
                .activityBackgroundTint(Color(red: 0.08, green: 0.09, blue: 0.12))
                .activitySystemActionForegroundColor(Color(red: 0.72, green: 0.88, blue: 0.92))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer")
                        .foregroundStyle(Color(red: 0.95, green: 0.72, blue: 0.35))
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exerciseName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        WorkoutRestCountdownText(state: context.state)
                    }
                    .padding(.horizontal, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WorkoutNextSetBadge(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.isOvertime ? "exclamationmark" : "timer")
                    .foregroundStyle(context.state.isOvertime ? .orange : Color(red: 0.72, green: 0.88, blue: 0.92))
            } compactTrailing: {
                WorkoutRestCountdownText(state: context.state, compact: true)
            } minimal: {
                Image(systemName: "timer")
            }
        }
    }
}

private struct WorkoutRestLockScreenView: View {
    let state: WorkoutRestAttributes.ContentState
    let attributes: WorkoutRestAttributes

    private let mint = Color(red: 0.40, green: 0.75, blue: 0.80)
    private let amber = Color(red: 0.95, green: 0.72, blue: 0.35)
    private let cream = Color(red: 0.94, green: 0.93, blue: 0.88)
    private let muted = Color(red: 0.55, green: 0.58, blue: 0.62)

    private var nextSetLabel: String {
        "\(state.weightLabel) × \(state.isAmrap ? "AMRAP" : "\(state.targetReps)")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(attributes.programName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text(attributes.dayLabel)
                        .font(.caption2)
                        .foregroundStyle(muted.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                WorkoutNextSetBadge(state: state)
            }

            Text(state.exerciseName)
                .font(.headline.weight(.bold))
                .foregroundStyle(cream)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.isOvertime ? "Over rest" : "Rest")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(state.isOvertime ? amber : muted)
                    WorkoutRestCountdownText(state: state, prominent: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Next set")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(muted)
                    Text(nextSetLabel)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(mint)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

private struct WorkoutRestCountdownText: View {
    let state: WorkoutRestAttributes.ContentState
    var compact = false
    var prominent = false

    var body: some View {
        Group {
            if state.isOvertime {
                Text("+\(state.overtimeSeconds)s")
                    .font((prominent ? Font.title2 : Font.caption).weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.orange)
            } else {
                Text(timerInterval: Date()...state.restEnd, countsDown: true)
                    .font((prominent ? Font.system(size: 32, weight: .bold, design: .rounded) : Font.caption).monospacedDigit())
                    .foregroundStyle(prominent ? Color(red: 0.95, green: 0.72, blue: 0.35) : Color(red: 0.72, green: 0.88, blue: 0.92))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
    }
}

private struct WorkoutNextSetBadge: View {
    let state: WorkoutRestAttributes.ContentState

    var body: some View {
        Text("Set \(state.setNumber)/\(state.totalSets)")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color(red: 0.94, green: 0.93, blue: 0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
    }
}
