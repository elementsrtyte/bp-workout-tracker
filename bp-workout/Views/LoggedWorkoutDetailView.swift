import SwiftData
import SwiftUI

/// Read-only summary of a saved session (e.g. from Calendar).
struct LoggedWorkoutDetailView: View {
    let workout: LoggedWorkout

    var body: some View {
        List {
            Section {
                LabeledContent("When") {
                    Text(workout.date.formatted(date: .abbreviated, time: .shortened))
                }
                if let p = workout.programName, !p.isEmpty {
                    LabeledContent("Program") { Text(p) }
                }
                if let d = workout.dayLabel, !d.isEmpty {
                    LabeledContent("Day") { Text(d) }
                }
                if let n = workout.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(n)
                        .font(.subheadline)
                        .foregroundStyle(BlueprintTheme.cream)
                }
            }

            ForEach(workout.exercises.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.id) { ex in
                Section {
                    if let sub = ex.prescribedName, !sub.isEmpty,
                       ExerciseNameNormalizer.key(sub) != ExerciseNameNormalizer.key(ex.name) {
                        Text("Prescribed: \(sub)")
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.amber)
                    }
                    ForEach(ex.sets.sorted(by: { $0.order < $1.order }), id: \.id) { s in
                        HStack {
                            Text("Set \(s.order + 1)")
                                .foregroundStyle(BlueprintTheme.mutedLight)
                            Spacer()
                            Group {
                                if s.weight == 0 {
                                    Text("BW × \(s.reps)")
                                } else {
                                    Text("\(WorkoutPrefill.formatWeight(s.weight)) × \(s.reps)")
                                }
                            }
                            .font(.body.weight(.medium).monospacedDigit())
                            .foregroundStyle(BlueprintTheme.cream)
                        }
                    }
                } header: {
                    Text(ex.name)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(BlueprintTheme.bg)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .tint(BlueprintTheme.purple)
    }
}
