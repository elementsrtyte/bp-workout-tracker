import SwiftData
import SwiftUI

/// Month grid highlighting days with at least one saved workout.
struct GymCalendarView: View {
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]

    @State private var monthAnchor: Date = .now
    @State private var selectedDay: Date?

    private var calendar: Calendar { .current }

    private var streakSnapshot: WorkoutWeeklyStreakEngine.Snapshot {
        let bundle = BundleDataStore.shared
        bundle.loadIfNeeded()
        let programs = bundle.workoutPrograms?.programs ?? []
        let id = UserDefaults.standard.string(forKey: "workoutHub.activeProgramId") ?? ""
        let program = programs.first { $0.id == id }
        return WorkoutWeeklyStreakEngine.snapshot(
            loggedWorkouts: loggedWorkouts,
            activeProgram: program
        )
    }

    private var workoutDays: Set<Date> {
        Set(loggedWorkouts.map { calendar.startOfDay(for: $0.date) })
    }

    private var monthStart: Date {
        let c = calendar.dateComponents([.year, .month], from: monthAnchor)
        return calendar.date(from: c) ?? monthAnchor
    }

    private var weekdayHeader: [String] {
        let syms = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(syms[first...] + syms[..<first])
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    private var leadingBlankDays: Int {
        let wd = calendar.component(.weekday, from: monthStart)
        let first = calendar.firstWeekday
        return (wd - first + 7) % 7
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: monthStart)
    }

    private var gymDaysThisMonth: Int {
        (1...daysInMonth).filter { day in
            guard let d = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { return false }
            return workoutDays.contains(calendar.startOfDay(for: d))
        }.count
    }

    private var totalDistinctGymDays: Int {
        workoutDays.count
    }

    private var workoutsForSelectedDay: [LoggedWorkout] {
        guard let sel = selectedDay else { return [] }
        let start = calendar.startOfDay(for: sel)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return loggedWorkouts.filter { $0.date >= start && $0.date < end }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryRow

                    WeeklyStreakPanel(snapshot: streakSnapshot)

                    monthNavigation

                    calendarCard

                    if let sel = selectedDay {
                        dayDetailSection(for: sel)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity)
            .background(BlueprintTheme.bg)
            .navigationTitle("Calendar")
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 12) {
            statPill(title: "This month", value: "\(gymDaysThisMonth)", subtitle: gymDaysThisMonth == 1 ? "gym day" : "gym days")
            statPill(title: "All time", value: "\(totalDistinctGymDays)", subtitle: totalDistinctGymDays == 1 ? "distinct day" : "distinct days")
        }
    }

    private func statPill(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(BlueprintTheme.cream)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(BlueprintTheme.mutedLight.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var monthNavigation: some View {
        HStack {
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlueprintTheme.lavender)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(monthTitle)
                .font(.headline)
                .foregroundStyle(BlueprintTheme.cream)

            Spacer()

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(BlueprintTheme.lavender)
            }
            .accessibilityLabel("Next month")
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(weekdayHeader, id: \.self) { sym in
                    Text(sym.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.muted)
                        .frame(maxWidth: .infinity)
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(0..<(leadingBlankDays + daysInMonth), id: \.self) { index in
                    if index < leadingBlankDays {
                        Color.clear
                            .frame(height: 44)
                    } else {
                        let day = index - leadingBlankDays + 1
                        dayCell(day: day)
                    }
                }
            }
        }
        .padding(14)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func dayCell(day: Int) -> some View {
        let cellDate = calendar.date(byAdding: .day, value: day - 1, to: monthStart) ?? monthStart
        let dayStart = calendar.startOfDay(for: cellDate)
        let hasWorkout = workoutDays.contains(dayStart)
        let isToday = calendar.isDateInToday(cellDate)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: cellDate) } ?? false

        return Button {
            selectedDay = dayStart
        } label: {
            ZStack {
                if hasWorkout {
                    Circle()
                        .fill(BlueprintTheme.mint.opacity(0.35))
                        .frame(width: 36, height: 36)
                    Circle()
                        .stroke(BlueprintTheme.mint, lineWidth: 2)
                        .frame(width: 36, height: 36)
                } else if isSelected {
                    Circle()
                        .stroke(BlueprintTheme.lavender.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 36, height: 36)
                }

                Text("\(day)")
                    .font(.callout.weight(hasWorkout || isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        hasWorkout || isSelected ? BlueprintTheme.cream : BlueprintTheme.mutedLight
                    )
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BlueprintTheme.purple.opacity(0.85), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityDayLabel(day: day, hasWorkout: hasWorkout, isToday: isToday))
    }

    private func accessibilityDayLabel(day: Int, hasWorkout: Bool, isToday: Bool) -> String {
        var parts = ["\(day)"]
        if hasWorkout { parts.append("workout logged") }
        if isToday { parts.append("today") }
        return parts.joined(separator: ", ")
    }

    private func dayDetailSection(for day: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.fullDateFormatter.string(from: day))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BlueprintTheme.cream)

            if workoutsForSelectedDay.isEmpty {
                Text("No workouts on this day.")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.muted)
            } else {
                ForEach(workoutsForSelectedDay) { w in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(BlueprintTheme.mint)
                            .frame(width: 4)
                            .padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.listSubtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(BlueprintTheme.cream)
                            Text(timeString(w.date))
                                .font(.caption2.monospacedDigit())
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
        }
    }

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .none
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private func shiftMonth(_ delta: Int) {
        if let d = calendar.date(byAdding: .month, value: delta, to: monthStart) {
            monthAnchor = d
            selectedDay = nil
        }
    }
}

