import SwiftData
import SwiftUI

struct LogWorkoutEditorView: View {
    @StateObject private var viewModel: LogWorkoutEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var loggedWorkouts: [LoggedWorkout]

    init(template: LogWorkoutTemplate?) {
        _viewModel = StateObject(wrappedValue: LogWorkoutEditorViewModel(template: template))
    }

    var body: some View {
        Form {
            Section("Session") {
                DatePicker("Date", selection: $viewModel.date, displayedComponents: .date)
                TextField("Program (optional)", text: $viewModel.programName)
                TextField("Day / focus (optional)", text: $viewModel.dayLabel)
            }

            Section("Exercises") {
                ForEach($viewModel.exercises) { $ex in
                    DisclosureGroup(ex.name.isEmpty ? "Exercise" : ex.name) {
                        TextField("Name", text: $ex.name)
                        ForEach($ex.sets) { $s in
                            HStack {
                                TextField("Weight", text: $s.weight)
                                #if os(iOS)
                                    .keyboardType(.decimalPad)
                                #endif
                                TextField("Reps", text: $s.reps)
                                #if os(iOS)
                                    .keyboardType(.numberPad)
                                #endif
                            }
                        }
                        .onDelete { idx in
                            ex.sets.remove(atOffsets: idx)
                        }
                        Button("Add set") {
                            ex.sets.append(DraftSet(weight: "", reps: ""))
                        }
                    }
                }
                .onDelete { viewModel.exercises.remove(atOffsets: $0) }

                Button("Add exercise") {
                    viewModel.exercises.append(DraftExercise(name: "", sets: [DraftSet(weight: "", reps: "")]))
                }
            }

            Section("Notes") {
                TextField("Notes", text: $viewModel.notes, axis: .vertical)
            }
        }
        .navigationTitle("New workout")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.save(modelContext: modelContext, onComplete: { dismiss() })
                }
                .disabled(!viewModel.canSave)
            }
        }
        .onAppear { viewModel.onAppear(loggedWorkoutsForPrefill: loggedWorkouts) }
    }
}
