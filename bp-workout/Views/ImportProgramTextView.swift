import SwiftUI
import UniformTypeIdentifiers

/// Paste or pick a text file; Blueprint API turns noisy plain text into a program template and optional history.
struct ImportProgramTextView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth: SupabaseSessionManager = .shared

    var onParsed: (ProgramImportResult) -> Void

    @State private var text = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false

    private var aiReady: Bool {
        BlueprintAPIConfig.isConfigured && auth.phase == .signedIn
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Paste exports, notes, or logs—even noisy text. The API builds your program template and pulls in dated workout history when it can (sets, reps, weights).")
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.mutedLight)
                        .fixedSize(horizontal: false, vertical: true)

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

                    Text("Past workouts need ISO dates (YYYY-MM-DD) in the source for history to import. Review the program in the editor before saving.")
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
        }
    }

    private var canParse: Bool {
        !busy
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && aiReady
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
            let result = try await OpenAIProgramImportService.importResult(fromPlainTextBody: content)
            onParsed(result)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
