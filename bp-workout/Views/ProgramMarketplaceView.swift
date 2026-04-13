import SwiftUI

/// Browse programs, add to profile, and create or (as admin) edit plans.
struct ProgramMarketplaceView: View {
    @EnvironmentObject private var programLibrary: UserProgramLibrary
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var bundle = BundleDataStore.shared

    @State private var search = ""
    @State private var editorRoute: ProgramEditorRoute?
    @State private var deleteTarget: WorkoutProgram?
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    introCard

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
                ToolbarItem(placement: .primaryAction) {
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Blueprint library")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            Text("Add programs to your profile for the Workout tab. Tap + to build your own plan. Turn on Program admin in Settings to edit bundled Blueprint plans on this device.")
                .font(.caption)
                .foregroundStyle(BlueprintTheme.mutedLight)
                .fixedSize(horizontal: false, vertical: true)
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
