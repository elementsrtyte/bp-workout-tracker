import SwiftData
import SwiftUI

/// Marketplace discovery, profile adds, custom programs, and catalog edits (Program admin or existing local override).
struct ProgramMarketplaceView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var programLibrary: UserProgramLibrary
    @EnvironmentObject private var appSettings: AppSettings
    @ObservedObject private var bundle = BundleDataStore.shared

    @State private var search = ""
    /// `nil` = show all categories in Discover.
    @State private var selectedCategorySlug: String?
    @State private var editorRoute: ProgramEditorRoute?
    @State private var deleteTarget: WorkoutProgram?
    @State private var showDeleteConfirm = false
    @State private var importFromTextPresented = false
    @State private var importSummaryMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    catalogStatusBanner

                    marketplaceHero

                    if !yourProgramsFiltered.isEmpty {
                        sectionHeader(title: "Your programs", subtitle: "Custom plans on this device")
                        LazyVGrid(columns: programGridColumns, spacing: 12) {
                            ForEach(yourProgramsFiltered) { program in
                                marketplaceProgramCard(program)
                            }
                        }
                    }

                    sectionHeader(title: "Discover", subtitle: "Add Blueprint programs to your profile")
                    categoryFilterChips

                    Group {
                        if discoverFiltered.isEmpty {
                            Text(
                                selectedCategorySlug == nil
                                    ? "No programs match your search."
                                    : "No programs in this category match your search."
                            )
                            .font(.subheadline)
                            .foregroundStyle(BlueprintTheme.mutedLight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                        } else {
                            ForEach(discoverShelfSections) { shelf in
                                VStack(alignment: .leading, spacing: 10) {
                                    sectionHeader(title: shelf.title, subtitle: shelf.subtitle)
                                    LazyVGrid(columns: programGridColumns, spacing: 12) {
                                        ForEach(shelf.programs) { program in
                                            marketplaceProgramCard(program)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
            .background(BlueprintTheme.bg)
            .blueprintDismissKeyboardOnScroll()
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
            .tint(BlueprintTheme.purple)
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
                    .environmentObject(appSettings)
            }
            .tint(BlueprintTheme.purple)
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

    private var marketplaceCategories: [CatalogCategory] {
        bundle.workoutPrograms?.categories ?? []
    }

    private var programGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
    }

    private func matchesSearch(_ p: WorkoutProgram, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        return p.name.lowercased().contains(query)
            || p.subtitle.lowercased().contains(query)
            || (p.categoryTitle?.lowercased().contains(query) ?? false)
    }

    private var searchQuery: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var yourProgramsFiltered: [WorkoutProgram] {
        catalog
            .filter { bundle.isPersistedCustomProgram(id: $0.id) }
            .filter { matchesSearch($0, query: searchQuery) }
    }

    private func matchesDiscoverCategory(_ p: WorkoutProgram) -> Bool {
        guard let slug = selectedCategorySlug else { return true }
        return p.categorySlug == slug
    }

    /// Catalog / bundled programs only (not device-local custom rows).
    private var discoverFiltered: [WorkoutProgram] {
        catalog
            .filter { !bundle.isPersistedCustomProgram(id: $0.id) }
            .filter { matchesSearch($0, query: searchQuery) }
            .filter { matchesDiscoverCategory($0) }
    }

    /// Grouped shelves under Discover (PPL, splits, full body, etc.).
    private var discoverShelfSections: [DiscoverShelfSection] {
        discoverShelfSections(for: discoverFiltered)
    }

    private struct DiscoverShelfSection: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let programs: [WorkoutProgram]
    }

    /// Fixed order for discover subsections.
    private static let discoverShelfDefinitions: [(id: String, title: String, subtitle: String)] = [
        ("featured", "Featured", "Curated picks, deloads, and resets"),
        ("ppl", "Push / pull / legs", "Rotate push, pull, and leg days"),
        ("splits", "Splits", "Upper/lower and classic multi-day splits"),
        ("full_body", "Full body", "Total-body sessions"),
        ("strength", "Strength & power", "Heavy compounds and barbell emphasis"),
        ("legs", "Legs & glutes", "Lower-body focused plans"),
        ("athletic", "Athletic & conditioning", "Circuits, performance, and durability"),
        ("beginner", "Beginner friendly", "Simple progressions and accessible equipment"),
        ("specialty", "Specialty", "Arms, machines-only, and niche blocks"),
    ]

    private func discoverShelfSections(for programs: [WorkoutProgram]) -> [DiscoverShelfSection] {
        var buckets: [String: [WorkoutProgram]] = [:]
        for p in programs {
            let key = discoverShelfKey(for: p)
            buckets[key, default: []].append(p)
        }
        return Self.discoverShelfDefinitions.compactMap { def in
            let list = (buckets[def.id] ?? []).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            guard !list.isEmpty else { return nil }
            return DiscoverShelfSection(id: def.id, title: def.title, subtitle: def.subtitle, programs: list)
        }
    }

    /// One shelf per program — uses known catalog ids, then name heuristics, then marketplace category.
    private func discoverShelfKey(for p: WorkoutProgram) -> String {
        switch p.id {
        case "mp-push-pull-legs", "program-6":
            return "ppl"
        case "mp-upper-lower-hypertrophy", "mp-starter-split",
            "program-1", "program-2", "program-3", "program-4", "program-5":
            return "splits"
        case "mp-full-body-3":
            return "full_body"
        case "mp-upper-power", "mp-lower-power", "mp-back-thickness", "mp-powerbuilding", "mp-press-specialist":
            return "strength"
        case "mp-glute-legs", "mp-lower-volume":
            return "legs"
        case "mp-conditioning-circuit", "mp-athletic-total", "mp-shoulder-health":
            return "athletic"
        case "mp-minimal-equipment", "mp-machine-only":
            return "beginner"
        case "mp-arm-focus":
            return "specialty"
        case "mp-deload-reset":
            return "featured"
        default:
            break
        }

        let blob = (p.name + " " + p.subtitle).lowercased()
        if blob.contains("deload") || blob.contains("recovery week") {
            return "featured"
        }
        if blob.contains("ppl")
            || blob.contains("push/pull/legs")
            || (blob.contains("push") && blob.contains("pull") && blob.contains("leg")) {
            return "ppl"
        }
        if blob.contains("full body") || blob.contains("full-body") || blob.contains("total body")
            || blob.contains("total-body") {
            return "full_body"
        }
        if blob.contains("upper") && blob.contains("lower") {
            return "splits"
        }

        switch p.categorySlug {
        case "featured":
            return "featured"
        case "beginner":
            return "beginner"
        case "athletic":
            return "athletic"
        case "specialty":
            return "specialty"
        case "strength":
            return "strength"
        case "hypertrophy":
            return "splits"
        default:
            return "splits"
        }
    }

    private var marketplaceHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Program marketplace")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            Text("Filter by focus, then browse plans grouped by style (PPL, splits, full body, and more). Add to your profile or build your own with +.")
                .font(.caption)
                .foregroundStyle(BlueprintTheme.mutedLight)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                importFromTextPresented = true
            } label: {
                Label("Import from text or file", systemImage: "doc.text.magnifyingglass")
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

    /// Copy for the card footer line: training frequency (days per week for typical templates) plus a short day-name preview.
    private func programDaysPerWeekDetail(_ program: WorkoutProgram) -> String {
        let n = program.days.count
        let perWeek: String
        switch n {
        case 0:
            perWeek = "No training days"
        case 1:
            perWeek = "1 day/week"
        default:
            perWeek = "\(n) days/week"
        }
        guard n > 0 else { return perWeek }
        let preview = program.days.map(\.label).prefix(2).joined(separator: ", ")
        let suffix = n > 2 ? "…" : ""
        return "\(perWeek) · \(preview)\(suffix)"
    }

    /// Accent for the program card stripe: greener for fewer training days in the template, redder for more (typical proxy for days/week).
    private func programTrainingLoadAccent(trainingDayCount: Int) -> Color {
        guard trainingDayCount > 0 else { return BlueprintTheme.muted }
        let minDays = 1
        let maxDays = 7
        let clamped = max(minDays, min(maxDays, trainingDayCount))
        let t = Double(clamped - minDays) / Double(maxDays - minDays)
        let hue = (120.0 / 360.0) * (1.0 - t)
        return Color(hue: hue, saturation: 0.78, brightness: 0.92)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .foregroundStyle(BlueprintTheme.cream)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(BlueprintTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChipLabel(title: "All", systemImage: "square.grid.2x2", slug: nil)
                ForEach(marketplaceCategories) { cat in
                    categoryChipLabel(title: cat.title, systemImage: cat.iconSfSymbol, slug: cat.slug)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func categoryChipLabel(title: String, systemImage: String, slug: String?) -> some View {
        let selected = selectedCategorySlug == slug
        return Button {
            selectedCategorySlug = slug
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? BlueprintTheme.cream : BlueprintTheme.mutedLight)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? BlueprintTheme.purple.opacity(0.38) : BlueprintTheme.cardInner)
            .overlay(
                Capsule()
                    .strokeBorder(
                        selected ? BlueprintTheme.lavender.opacity(0.55) : BlueprintTheme.border,
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var catalogStatusBanner: some View {
        if bundle.isRefreshingCatalog {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(BlueprintTheme.lavender)
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

    @ViewBuilder
    private func programCardBadges(
        program: WorkoutProgram,
        userOwned: Bool,
        bundled: Bool,
        inProfile: Bool
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let cat = program.categoryTitle, !userOwned {
                    Text(cat.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.lavender)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BlueprintTheme.lavender.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .lineLimit(1)
                }
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
                if inProfile {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2.weight(.semibold))
                        Text("In profile")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(BlueprintTheme.mint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(BlueprintTheme.mint.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    private func marketplaceProgramCard(_ program: WorkoutProgram) -> some View {
        let accent = programTrainingLoadAccent(trainingDayCount: program.days.count)
        let inProfile = programLibrary.isInLibrary(programId: program.id, catalog: catalog)
        let bundled = bundle.isBundledProgram(id: program.id)
        let userOwned = bundle.isPersistedCustomProgram(id: program.id)
        let showEdit =
            userOwned
            || (bundled
                && (appSettings.programAdminMode || bundle.hasBundledOverride(programId: program.id)))
        let showDelete = userOwned

        let hasOverflowActions = showEdit || showDelete || inProfile

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(accent.opacity(0.9))
                    .frame(width: 4)
                    .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(program.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.cream)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if hasOverflowActions {
                            Menu {
                                if showEdit {
                                    Button {
                                        if userOwned {
                                            editorRoute = .editCustom(program)
                                        } else {
                                            editorRoute = .editBundled(program)
                                        }
                                    } label: {
                                        Label("Edit program", systemImage: "pencil")
                                    }
                                }
                                if inProfile {
                                    Button {
                                        programLibrary.setProgramInLibrary(program.id, enabled: false, catalog: catalog)
                                        if bundled {
                                            bundle.noteBundledProgramProfileMembershipChange(programId: program.id, enabled: false)
                                        }
                                    } label: {
                                        Label("Remove from profile", systemImage: "person.crop.circle.badge.minus")
                                    }
                                }
                                if showDelete {
                                    Button(role: .destructive) {
                                        deleteTarget = program
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(BlueprintTheme.mutedLight)
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("More actions")
                        }
                    }

                    programCardBadges(
                        program: program,
                        userOwned: userOwned,
                        bundled: bundled,
                        inProfile: inProfile
                    )

                    Text(program.subtitle)
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.mutedLight)
                        .lineLimit(2)
                    Text(programDaysPerWeekDetail(program))
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.muted)
                        .lineLimit(2)
                }
            }

            if !inProfile {
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
                .foregroundStyle(BlueprintTheme.cream)
            }
        }
        .padding(14)
        .background(BlueprintTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
