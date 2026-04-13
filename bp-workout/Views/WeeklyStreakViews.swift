import SwiftUI

// MARK: - Full panel (Calendar, etc.)

struct WeeklyStreakPanel: View {
    let snapshot: WorkoutWeeklyStreakEngine.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly streak")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(snapshot.currentStreakWeeks)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(BlueprintTheme.cream)
                        Text(snapshot.currentStreakWeeks == 1 ? "week" : "weeks")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BlueprintTheme.mutedLight)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BlueprintTheme.amber, Color.orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating.speed(0.35), value: snapshot.currentStreakWeeks > 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("This week")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.lavender.opacity(0.95))
                    Spacer()
                    Text("\(snapshot.currentWeekSessions)/\(snapshot.requiredSessionsPerWeek) sessions")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(BlueprintTheme.cream)
                }
                GeometryReader { geo in
                    let p = min(1, Double(snapshot.currentWeekSessions) / Double(max(1, snapshot.requiredSessionsPerWeek)))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(BlueprintTheme.cardInner)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [BlueprintTheme.mint, BlueprintTheme.mint.opacity(0.65)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, geo.size.width * CGFloat(p)))
                    }
                }
                .frame(height: 8)
            }

            Text(goalCaption)
                .font(.caption2)
                .foregroundStyle(BlueprintTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text("Best run: \(snapshot.bestStreakWeeks) \(snapshot.bestStreakWeeks == 1 ? "week" : "weeks")")
                .font(.caption2.weight(.medium))
                .foregroundStyle(BlueprintTheme.mutedLight.opacity(0.9))

            medalRow
        }
        .padding(14)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var goalCaption: String {
        if let name = snapshot.programFilterName {
            return "Goal: \(snapshot.requiredSessionsPerWeek)× per week · counts workouts saved under “\(name)”."
        }
        return "Goal: \(snapshot.requiredSessionsPerWeek)× per week · all saved workouts count."
    }

    private var medalRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Awards")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(WorkoutWeeklyStreakEngine.medals) { medal in
                        StreakMedalBadge(medal: medal, unlocked: snapshot.bestStreakWeeks >= medal.weeksRequired)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Compact teaser (Workout tab)

struct WeeklyStreakTeaser: View {
    let snapshot: WorkoutWeeklyStreakEngine.Snapshot

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title3)
                .foregroundStyle(BlueprintTheme.amber)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(snapshot.currentStreakWeeks)-week streak · \(snapshot.currentWeekSessions)/\(snapshot.requiredSessionsPerWeek) this week")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.cream)
                Text("Hit your weekly target to keep it going.")
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(BlueprintTheme.cardInner)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Medal cell

private struct StreakMedalBadge: View {
    let medal: WorkoutWeeklyStreakEngine.Medal
    let unlocked: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(unlocked ? BlueprintTheme.cardInner : BlueprintTheme.cardInner.opacity(0.5))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Circle()
                            .stroke(unlocked ? BlueprintTheme.amber.opacity(0.85) : BlueprintTheme.border, lineWidth: unlocked ? 2 : 1)
                    )
                Image(systemName: medal.systemImage)
                    .font(.title2)
                    .foregroundStyle(unlocked ? BlueprintTheme.amber : BlueprintTheme.mutedLight.opacity(0.72))
                if !unlocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.mutedLight.opacity(0.9))
                        .offset(x: 16, y: 16)
                }
            }
            Text(medal.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(unlocked ? BlueprintTheme.cream : BlueprintTheme.mutedLight.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 88)
            Text("\(medal.weeksRequired) wk")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(BlueprintTheme.mutedLight.opacity(0.95))
        }
    }
}
