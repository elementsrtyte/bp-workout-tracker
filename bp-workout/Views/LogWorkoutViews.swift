import SwiftData
import SwiftUI

struct LogWorkoutListView: View {
    @Query(sort: \LoggedWorkout.date, order: .reverse) private var workouts: [LoggedWorkout]
    @State private var editorTemplate: LogWorkoutTemplate?
    @State private var showBlankEditor = false

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            List {
                ForEach(workouts) { w in
                    NavigationLink {
                        LogWorkoutDetailView(workout: w)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.headline)
                            Text(w.listSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Log")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New blank workout") {
                            showBlankEditor = true
                        }
                        Button("From program…") {
                            editorTemplate = LogWorkoutTemplate(programName: nil, dayLabel: nil)
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showBlankEditor) {
                NavigationStack {
                    LogWorkoutEditorView(template: nil)
                }
            }
            .sheet(item: $editorTemplate) { tpl in
                NavigationStack {
                    LogWorkoutEditorView(template: tpl)
                }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for i in offsets {
            modelContext.delete(workouts[i])
        }
    }
}

struct LogWorkoutDetailView: View {
    var workout: LoggedWorkout

    var body: some View {
        List {
            Section("Info") {
                LabeledContent("Date", value: workout.date.formatted(date: .long, time: .omitted))
                if let p = workout.programName {
                    LabeledContent("Program", value: p)
                }
                if let d = workout.dayLabel {
                    LabeledContent("Day", value: d)
                }
            }
            ForEach(workout.exercises.sorted(by: { $0.sortOrder < $1.sortOrder })) { ex in
                Section(ex.name) {
                    ForEach(ex.sets.sorted(by: { $0.order < $1.order })) { s in
                        HStack {
                            Text("\(formatWeight(s.weight)) lbs")
                            Text("×")
                            Text("\(s.reps) reps")
                        }
                    }
                }
            }
        }
        .navigationTitle("Workout")
    }

    private func formatWeight(_ w: Double) -> String {
        w.formatted(.number.precision(.fractionLength(0...1)))
    }
}

struct LogWorkoutEditorView: View {
    @StateObject private var viewModel: LogWorkoutEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
        .onAppear { viewModel.onAppear() }
    }
}
