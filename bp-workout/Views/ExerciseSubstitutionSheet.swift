import SwiftUI

/// Session-only exercise swap from the Workout hub (does not edit the saved program).
struct ExerciseSubstitutionSheet: View {
    let prescribedName: String
    let currentName: String
    let rowId: String
    let hasLoggedSets: Bool
    let catalogExerciseNames: [String]
    @ObservedObject var viewModel: WorkoutHubViewModel
    @ObservedObject private var auth: SupabaseSessionManager = .shared

    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String = ""
    @State private var gymNote: String = ""
    @State private var aiSuggestions: [String] = []
    @State private var aiError: String?
    @State private var aiLoading = false
    @State private var showLoggedSetsConfirm = false
    @State private var pendingApplyName: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Prescribed") {
                        Text(prescribedName)
                            .foregroundStyle(BlueprintTheme.cream)
                            .multilineTextAlignment(.trailing)
                    }
                    if currentName != prescribedName {
                        LabeledContent("This session") {
                            Text(currentName)
                                .foregroundStyle(BlueprintTheme.mutedLight)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("Use instead") {
                    TextField("Exercise name", text: $draftName)
                        .foregroundStyle(BlueprintTheme.cream)
                        .autocorrectionDisabled()
                    Button("Apply typed name") {
                        attemptApply(draftName)
                    }
                    .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Similar in your catalog") {
                    if localPicks.isEmpty {
                        Text("No close matches — type a name or try AI.")
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                    } else {
                        ForEach(localPicks, id: \.self) { name in
                            Button(name) {
                                attemptApply(name)
                            }
                            .foregroundStyle(BlueprintTheme.cream)
                        }
                    }
                }

                Section("AI ideas") {
                    TextField("Optional context (equipment, injuries…)", text: $gymNote, axis: .vertical)
                        .lineLimit(2 ... 4)
                        .foregroundStyle(BlueprintTheme.cream)
                    if !BlueprintAPIConfig.isConfigured || auth.phase != .signedIn {
                        Text(
                            !BlueprintAPIConfig.isConfigured
                                ? "Blueprint API URL is not configured."
                                : "Sign in to load AI suggestions (server-side OpenAI)."
                        )
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.mutedLight)
                    } else {
                        Button {
                            Task { await loadAI() }
                        } label: {
                            HStack {
                                if aiLoading {
                                    ProgressView()
                                        .tint(BlueprintTheme.lavender)
                                }
                                Text(aiLoading ? "Loading…" : "Suggest alternatives")
                            }
                        }
                        .disabled(aiLoading)
                        if let aiError {
                            Text(aiError)
                                .font(.caption)
                                .foregroundStyle(BlueprintTheme.danger)
                        }
                        ForEach(aiSuggestions, id: \.self) { name in
                            Button(name) {
                                attemptApply(name)
                            }
                            .foregroundStyle(BlueprintTheme.cream)
                        }
                    }
                }

                if hasLoggedSets {
                    Section {
                        Text("Applying a swap clears logged sets for this exercise so the session stays consistent.")
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                    }
                }

                if currentName != prescribedName, !hasLoggedSets {
                    Section {
                        Button("Revert to prescribed exercise") {
                            viewModel.revertSessionExerciseSubstitution(rowId: rowId)
                            dismiss()
                        }
                        .foregroundStyle(BlueprintTheme.lavender)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(BlueprintTheme.bg)
            .blueprintDismissKeyboardOnScroll()
            .navigationTitle("Swap exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(BlueprintTheme.lavender)
                }
            }
            .onAppear {
                if draftName.isEmpty {
                    draftName = currentName
                }
            }
            .confirmationDialog(
                "Clear logged sets?",
                isPresented: $showLoggedSetsConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear and swap", role: .destructive) {
                    if let n = pendingApplyName {
                        commitApply(n, clearLoggedSets: true)
                    }
                    pendingApplyName = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingApplyName = nil
                }
            } message: {
                Text("You’ve already logged sets for this slot. Swapping exercises clears them for this session.")
            }
            .tint(BlueprintTheme.purple)
        }
    }

    private var localPicks: [String] {
        ExerciseSubstitutionSuggestions.localSuggestions(
            prescribedName: prescribedName,
            catalogNames: catalogExerciseNames
        )
    }

    private func attemptApply(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if t.caseInsensitiveCompare(prescribedName) == .orderedSame {
            viewModel.revertSessionExerciseSubstitution(rowId: rowId)
            dismiss()
            return
        }
        if hasLoggedSets {
            pendingApplyName = t
            showLoggedSetsConfirm = true
        } else {
            commitApply(t, clearLoggedSets: false)
        }
    }

    private func commitApply(_ name: String, clearLoggedSets: Bool) {
        viewModel.applySessionExerciseSubstitution(
            rowId: rowId,
            newDisplayName: name,
            clearLoggedSets: clearLoggedSets
        )
        dismiss()
    }

    private func loadAI() async {
        guard BlueprintAPIConfig.isConfigured, auth.phase == .signedIn else { return }
        aiLoading = true
        aiError = nil
        aiSuggestions = []
        defer { aiLoading = false }
        do {
            let list = try await OpenAIExerciseSubstitutionClient.fetchAlternatives(
                prescribedExercise: prescribedName,
                userNote: gymNote.isEmpty ? nil : gymNote
            )
            await MainActor.run {
                aiSuggestions = list
                if list.isEmpty {
                    aiError = "No suggestions parsed. Try again or pick from the list above."
                }
            }
        } catch {
            await MainActor.run {
                aiError = error.localizedDescription
            }
        }
    }
}
