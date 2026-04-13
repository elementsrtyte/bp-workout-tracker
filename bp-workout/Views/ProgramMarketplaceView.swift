import SwiftData
import SwiftUI

/// Browse programs, add to profile, and create or (as admin) edit plans.
struct ProgramMarketplaceView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var programLibrary: UserProgramLibrary
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var bundle = BundleDataStore.shared

    @State private var search = ""
    @State private var editorRoute: ProgramEditorRoute?
    @State private var deleteTarget: WorkoutProgram?
    @State private var showDeleteConfirm = false
    @State private var importFromTextPresented = false
    @State private var importSummaryMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    introCard
                    catalogStatusBanner

                    LazyVStack(spacing: 12) {
                        ForEach(filteredCatalog) { program in
                            marketplaceProgramCard(program)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
            .background(BlueprintTheme.bg)
            .navigationTitle("Programs")
            .searchable(text: $search, prompt: "Search programs")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        importFromTextPresented = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("Import program from text")

                    Button {
                        editorRoute = .create
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("New program")
                }
            }
        }
        .onAppear { bundle.loadIfNeeded() }
        .sheet(isPresented: $importFromTextPresented) {
            ImportProgramTextView { result in
                editorRoute = .createFromImport(result.program)
                if !result.historicalWorkouts.isEmpty {
                    Task { @MainActor in
                        do {
                            let inserted = try ImportHistoryPersistence.apply(
                                result.historicalWorkouts,
                                programId: result.program.id,
                                programName: result.program.name,
                                modelContext: modelContext
                            )
                            for w in inserted {
                                await BlueprintWorkoutSyncClient.push(w)
                            }
                            importSummaryMessage =
                                "Imported \(inserted.count) past workout\(inserted.count == 1 ? "" : "s") into your log."
                        } catch {
                            importSummaryMessage =
                                "Program opened, but history import failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
        .alert("Import", isPresented: Binding(
            get: { importSummaryMessage != nil },
            set: { if !$0 { importSummaryMessage = nil } }
        )) {
            Button("OK", role: .cancel) { importSummaryMessage = nil }
        } message: {
            Text(importSummaryMessage ?? "")
        }
        .sheet(item: $editorRoute) { route in
            NavigationStack {
                ProgramEditorView(route: route)
                    .environmentObject(programLibrary)
            }
        }
        .confirmationDialog(
            "Delete this program?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let program = deleteTarget {
                    programLibrary.setProgramInLibrary(program.id, enabled: false, catalog: catalog)
                    bundle.deleteCustomProgram(id: program.id)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text("This removes it from your device. Workout history is unchanged.")
        }
    }

    private var catalog: [WorkoutProgram] {
        bundle.mergedPrograms
    }

    private var filteredCatalog: [WorkoutProgram] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return catalog }
        return catalog.filter { p in
            p.name.lowercased().contains(q)
                || p.subtitle.lowercased().contains(q)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blueprint library")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            Text("Add programs to your profile for the Workout tab. Create a new plan with +, or import messy text / files: the API builds the program and can add dated workout history (YYYY-MM-DD) to your log. Turn on Program admin in Settings to edit bundled plans on this device.")
                .font(.caption)
                .foregroundStyle(BlueprintTheme.mutedLight)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                importFromTextPresented = true
            } label: {
                Label("Import workout from text or file", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(BlueprintTheme.lavender)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var catalogStatusBanner: some View {
        if bundle.isRefreshingCatalog {
            HStack(spacing: 10) {
                ProgressView()
                Text("Updating catalog…")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.mutedLight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(BlueprintTheme.card.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let msg = bundle.catalogSyncMessage {
            VStack(alignment: .leading, spacing: 8) {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await bundle.refreshCatalogFromServer() }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(BlueprintTheme.lavender)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(BlueprintTheme.card.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func marketplaceProgramCard(_ program: WorkoutProgram) -> some View {
        let accent = Color(hex: program.color)
        let inProfile = programLibrary.isInLibrary(programId: program.id, catalog: catalog)
        let bundled = bundle.isBundledProgram(id: program.id)
        let userOwned = bundle.isPersistedCustomProgram(id: program.id)
        let canEditBundled = appSettings.programAdminMode && bundled
        let showEdit = userOwned || canEditBundled
        let showDelete = userOwned

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(accent.opacity(0.9))
                    .frame(width: 5)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(program.name)
                            .font(.headline)
                            .foregroundStyle(BlueprintTheme.cream)
                        if userOwned {
                            Text("YOURS")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BlueprintTheme.mint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BlueprintTheme.mint.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else if bundled, bundle.hasBundledOverride(programId: program.id) {
                            Text("EDITED")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BlueprintTheme.amber)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BlueprintTheme.amber.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        Spacer(minLength: 0)
                        if inProfile {
                            Label("In profile", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BlueprintTheme.mint)
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("In your profile")
                        }
                    }
                    Text(program.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(BlueprintTheme.mutedLight)
                    Text("\(program.days.count) training days · \(program.days.map(\.label).prefix(2).joined(separator: ", "))\(program.days.count > 2 ? "…" : "")")
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.muted)
                        .lineLimit(2)
                }
            }

            if showEdit || showDelete {
                HStack(spacing: 10) {
                    if showEdit {
                        Button {
                            if userOwned {
                                editorRoute = .editCustom(program)
                            } else {
                                editorRoute = .editBundled(program)
                            }
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BlueprintTheme.lavender)
                    }
                    if showDelete {
                        Button {
                            deleteTarget = program
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(BlueprintTheme.danger)
                    }
                }
                .foregroundStyle(BlueprintTheme.cream)
            }

            Group {
                if inProfile {
                    Button {
                        programLibrary.setProgramInLibrary(program.id, enabled: false, catalog: catalog)
                        if bundled {
                            bundle.noteBundledProgramProfileMembershipChange(programId: program.id, enabled: false)
                        }
                    } label: {
                        Text("Remove from profile")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(BlueprintTheme.muted)
                } else {
                    Button {
                        programLibrary.setProgramInLibrary(program.id, enabled: true, catalog: catalog)
                        if bundled {
                            bundle.noteBundledProgramProfileMembershipChange(programId: program.id, enabled: true)
                        }
                    } label: {
                        Text("Add to profile")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BlueprintTheme.purple)
                }
            }
            .foregroundStyle(BlueprintTheme.cream)
        }
        .padding(14)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
