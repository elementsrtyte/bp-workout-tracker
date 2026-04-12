import SwiftUI

private let heroURL = URL(
    string: "https://d2xsxph8kpxj0f.cloudfront.net/310419663029914027/d4kuLRzxSXM9nrbbRPcbea/hero-banner-CmAYwVoABDY9NRPZkQCsYj.webp"
)!

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                if let stats = viewModel.stats {
                    statsStrip(stats)
                }
                let programs = viewModel.programs
                if !programs.isEmpty {
                    programSection(programs)
                    dayAndTable(programs)
                }
            }
        }
        .background(BlueprintTheme.bg)
        .navigationTitle("Programs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewModel.logTemplate) { tpl in
            NavigationStack {
                LogWorkoutEditorView(template: tpl)
            }
        }
        .onAppear { viewModel.onAppear() }
    }

    private func programSection(_ programs: [WorkoutProgram]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training programs")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BlueprintTheme.lavender)
                .padding(.horizontal, 20)
                .padding(.top, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(programs) { program in
                        ProgramChip(program: program, isSelected: program.id == viewModel.activeProgramId) {
                            viewModel.selectProgram(id: program.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func dayAndTable(_ programs: [WorkoutProgram]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let p = viewModel.activeProgram {
                HStack {
                    Text(p.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.cream)
                    if p.isUserCreated == true {
                        Text("SELF-CREATED")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BlueprintTheme.mint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(BlueprintTheme.mint.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Text("\(p.subtitle) · \(p.period)")
                    .font(.caption)
                    .foregroundStyle(BlueprintTheme.muted)
                    .padding(.horizontal, 20)

                Picker("Day", selection: $viewModel.dayIndex) {
                    ForEach(Array(p.days.enumerated()), id: \.offset) { i, day in
                        Text(day.label).tag(i)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                if viewModel.dayIndex < p.days.count {
                    let day = p.days[viewModel.dayIndex]
                    ExerciseTable(day: day)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 24)

                    Button {
                        viewModel.beginLogCurrentDay(programName: p.name, dayLabel: day.label)
                    } label: {
                        Label("Log this day", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BlueprintTheme.purple)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: heroURL) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(BlueprintTheme.card)
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Rectangle().fill(BlueprintTheme.card)
                @unknown default:
                    EmptyView()
                }
            }
            .frame(height: 220)
            .clipped()
            .overlay {
                LinearGradient(
                    colors: [BlueprintTheme.bg.opacity(0.95), BlueprintTheme.bg.opacity(0.2)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Rectangle()
                        .fill(BlueprintTheme.lavender)
                        .frame(width: 8, height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    Text("Training Log")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.lavender)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Neil Bhargava")
                        .font(.title.weight(.medium))
                        .foregroundStyle(BlueprintTheme.cream)
                    Text("Workout Programs")
                        .font(.title.weight(.medium))
                        .foregroundStyle(BlueprintTheme.mint)
                }

                if let stats = viewModel.stats {
                    Text("\(stats.totalPrograms) trainer-designed programs across \(stats.totalMonths) months of consistent training.")
                        .font(.subheadline)
                        .foregroundStyle(BlueprintTheme.muted)
                        .frame(maxWidth: 320, alignment: .leading)
                }
            }
            .padding(20)
        }
    }

    private func statsStrip(_ stats: ProgramStats) -> some View {
        VStack(spacing: 0) {
            Divider().background(BlueprintTheme.border)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCell(title: "Programs", value: "\(stats.totalPrograms)", icon: "trophy.fill")
                StatCell(title: "Months active", value: "\(stats.totalMonths)", icon: "calendar")
                StatCell(title: "Workout days", value: "\(stats.totalWorkoutDays)", icon: "chart.line.uptrend.xyaxis")
                StatCell(title: "Date range", value: "Apr '23 – Jan '25", icon: "dumbbell.fill")
            }
            .padding(16)
            .background(BlueprintTheme.card)
            Divider().background(BlueprintTheme.border)
        }
    }
}

private struct StatCell: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(BlueprintTheme.mint)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.cream)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProgramChip: View {
    let program: WorkoutProgram
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(program.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? BlueprintTheme.cream : BlueprintTheme.mutedLight)
                    if program.isUserCreated == true {
                        Text("SELF")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(BlueprintTheme.mint)
                    }
                }
                Text(program.subtitle)
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.muted)
                Text(program.period)
                    .font(.caption2)
                    .foregroundStyle(BlueprintTheme.muted)
            }
            .padding(12)
            .frame(width: 200, alignment: .leading)
            .background(isSelected ? BlueprintTheme.purple.opacity(0.2) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? BlueprintTheme.purple : BlueprintTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct ExerciseTable: View {
    let day: WorkoutDay

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Exercise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Max weight")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.muted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(BlueprintTheme.cardInner)

            ForEach(day.exercises) { ex in
                HStack(alignment: .top) {
                    HStack(spacing: 8) {
                        Rectangle()
                            .fill(BlueprintTheme.mint)
                            .frame(width: 6, height: 6)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        Text(ex.name)
                            .font(.subheadline)
                            .foregroundStyle(BlueprintTheme.cream)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(ex.maxWeight)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isBodyweight(ex.maxWeight) ? BlueprintTheme.muted : BlueprintTheme.lavender)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isBodyweight(ex.maxWeight) ? Color.white.opacity(0.05) : BlueprintTheme.purple.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(BlueprintTheme.card)
                Divider().background(BlueprintTheme.border)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(BlueprintTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func isBodyweight(_ s: String) -> Bool {
        s.lowercased().contains("bodyweight")
    }
}
