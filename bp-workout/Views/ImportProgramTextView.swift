import SwiftUI
import UniformTypeIdentifiers

/// Paste or pick a text file; user picks import type first, then Blueprint API parses with the right prompt.
struct ImportProgramTextView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var programLibrary: UserProgramLibrary
    @ObservedObject private var bundle = BundleDataStore.shared
    @ObservedObject private var auth: AuthSessionManager = .shared

    var onParsed: (ProgramImportOutcome) -> Void

    @State private var contentKind: ProgramImportContentKind = .newProgram
    @State private var selectedProgramId: String = ""
    @State private var dayLabelHint: String = ""
    @State private var text = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false

    private var aiReady: Bool {
        BlueprintAPIConfig.isConfigured && auth.phase == .signedIn
    }

    private var profilePrograms: [WorkoutProgram] {
        programLibrary.programsInProfile(from: bundle.mergedPrograms)
    }

    private var selectedProgram: WorkoutProgram? {
        profilePrograms.first { $0.id == selectedProgramId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Choose what you’re importing so the parser can focus. Then paste notes, exports, or logs—even without exact dates.")
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .fixedSize(horizontal: false, vertical: true)

                        BlueprintMenuPicker(
                            title: "Data type",
                            selection: $contentKind,
                            options: ProgramImportContentKind.allCases.map { ($0, $0.title) }
                        )

                        Text(contentKind.detail)
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                        if contentKind != .newProgram {
                            if profilePrograms.isEmpty {
                                Text("Add at least one program to your profile (Programs tab) to attach logs or a new day.")
                                    .font(.caption)
                                    .foregroundStyle(BlueprintTheme.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                BlueprintMenuPicker(
                                    title: "Program",
                                    selection: Binding(
                                        get: { selectedProgramId },
                                        set: { selectedProgramId = $0 }
                                    ),
                                    options: profilePrograms.map { ($0.id, $0.name) }
                                )
                            }
                        }

                        if contentKind == .newTrainingDay {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Day label hint (optional)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(BlueprintTheme.muted)
                                TextField("e.g. Pull B, Day 4", text: $dayLabelHint)
                                    .textFieldStyle(.plain)
                                    .font(.subheadline)
                                    .foregroundStyle(BlueprintTheme.cream)
                                    .padding(12)
                                    .background(BlueprintTheme.cardInner)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(BlueprintTheme.border, lineWidth: 1)
                                    )
                            }
                        }

                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Choose text file…", systemImage: "doc.badge.plus")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(BlueprintTheme.lavender)
                        .disabled(!aiReady)

                        TextEditor(text: $text)
                            .font(.body)
                            .foregroundStyle(BlueprintTheme.cream)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .padding(12)
                            .background(BlueprintTheme.cardInner)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(BlueprintTheme.border, lineWidth: 1)
                            )

                        if !aiReady {
                            Text(
                                !BlueprintAPIConfig.isConfigured
                                    ? "Blueprint API URL is not configured. Set BLUEPRINT_API_URL (e.g. http://127.0.0.1:8787) and run the api server."
                                    : "Sign in to use import. Your session is sent with each request."
                            )
                            .font(.caption)
                            .foregroundStyle(BlueprintTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(BlueprintTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(footerHint)
                            .font(.caption2)
                            .foregroundStyle(BlueprintTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(BlueprintTheme.bg)
                .blueprintDismissKeyboardOnScroll()

                if busy {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    ProgressView("Parsing…")
                        .tint(BlueprintTheme.lavender)
                        .foregroundStyle(BlueprintTheme.cream)
                        .padding(24)
                        .background(BlueprintTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .background(BlueprintTheme.bg)
            .navigationTitle("Import from text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(BlueprintTheme.lavender)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Parse") {
                        Task { await parse() }
                    }
                    .disabled(!canParse)
                    .foregroundStyle(canParse ? BlueprintTheme.cream : BlueprintTheme.muted)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.plainText, .utf8PlainText, .text],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task { await loadTextFile(url: url) }
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
            .tint(BlueprintTheme.purple)
            .onAppear {
                bundle.loadIfNeeded()
                reconcileProgramSelection()
            }
            .onChange(of: contentKind) { _, _ in
                reconcileProgramSelection()
            }
            .onChange(of: programLibrary.updateCounter) { _, _ in
                reconcileProgramSelection()
            }
            .onChange(of: bundle.userProgramsRevision) { _, _ in
                reconcileProgramSelection()
            }
        }
    }

    private var footerHint: String {
        switch contentKind {
        case .newProgram:
            return "Review the program in the editor before saving. Past workouts import when the model finds sets in your paste; dates help but are optional—placeholders are used when missing."
        case .workoutLog:
            return "Sessions without calendar dates still import: the app assigns recent placeholder days (you can edit dates in the log). Order in your paste is treated as newest-first at the top when dates are missing."
        case .newTrainingDay:
            return "You’ll open the program editor with the new day appended. Rename or reorder there if needed."
        }
    }

    private var canParse: Bool {
        guard !busy,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              aiReady
        else { return false }
        switch contentKind {
        case .newProgram:
            return true
        case .workoutLog, .newTrainingDay:
            return !selectedProgramId.isEmpty && selectedProgram != nil
        }
    }

    private func reconcileProgramSelection() {
        if contentKind == .newProgram {
            selectedProgramId = ""
            return
        }
        guard !profilePrograms.isEmpty else {
            selectedProgramId = ""
            return
        }
        if selectedProgramId.isEmpty || !profilePrograms.contains(where: { $0.id == selectedProgramId }) {
            selectedProgramId = profilePrograms[0].id
        }
    }

    private func loadTextFile(url: URL) async {
        errorMessage = nil
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let s = try String(contentsOf: url, encoding: .utf8)
            await MainActor.run {
                text = s
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func parse() async {
        errorMessage = nil
        busy = true
        defer { busy = false }
        guard aiReady else {
            errorMessage = "Sign in and configure the Blueprint API to import."
            return
        }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let result = try await OpenAIProgramImportService.importResult(
                text: content,
                contentKind: contentKind,
                selectedProgram: selectedProgram,
                trainingDayLabelHint: contentKind == .newTrainingDay ? dayLabelHint : nil
            )
            let outcome = ProgramImportOutcome(
                contentKind: contentKind,
                selectedProgram: selectedProgram,
                result: result
            )
            onParsed(outcome)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
