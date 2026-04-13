import SwiftUI

/// Browse bundled Blueprint programs and choose which appear on the Workout tab.
struct ProgramMarketplaceView: View {
    @EnvironmentObject private var programLibrary: UserProgramLibrary
    @ObservedObject private var bundle = BundleDataStore.shared

    @State private var search = ""

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
        }
        .onAppear { bundle.loadIfNeeded() }
    }

    private var catalog: [WorkoutProgram] {
        bundle.workoutPrograms?.programs ?? []
    }

    private var filteredCatalog: [WorkoutProgram] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return catalog }
        return catalog.filter { p in
            p.name.lowercased().contains(q)
                || p.subtitle.lowercased().contains(q)
                || p.period.lowercased().contains(q)
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Blueprint library")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            Text("Add programs to your profile to use them on the Workout tab. You can remove any you’re not running right now.")
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
                        if program.isUserCreated == true {
                            Text("SELF-CREATED")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(BlueprintTheme.mint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(BlueprintTheme.mint.opacity(0.15))
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
                    Text(program.period)
                        .font(.caption)
                        .foregroundStyle(BlueprintTheme.muted)
                    Text("\(program.days.count) training days · \(program.days.map(\.label).prefix(2).joined(separator: ", "))\(program.days.count > 2 ? "…" : "")")
                        .font(.caption2)
                        .foregroundStyle(BlueprintTheme.muted)
                        .lineLimit(2)
                }
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
