import SwiftUI

// MARK: - Menu card (long lists)

/// Card-styled control that reveals a `Menu` + inline `Picker` (system sheet), matching Blueprint surfaces.
struct BlueprintMenuPicker<Selection: Hashable>: View {
    var title: String = ""
    @Binding var selection: Selection
    let options: [(Selection, String)]

    private var displayText: String {
        options.first { $0.0 == selection }?.1 ?? options.first?.1 ?? "Choose"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.muted)
            }
            Menu {
                Picker(title.isEmpty ? "Choose" : title, selection: $selection) {
                    ForEach(options, id: \.0) { pair in
                        Text(pair.1).tag(pair.0)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(displayText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BlueprintTheme.cream)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BlueprintTheme.muted)
                        .imageScale(.small)
                }
                .padding(14)
                .background(BlueprintTheme.cardInner)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BlueprintTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Chip row (few options)

/// Capsule chips aligned with program day pills / superset selector.
struct BlueprintChipPicker<Selection: Hashable>: View {
    var title: String = ""
    @Binding var selection: Selection
    let options: [(Selection, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BlueprintTheme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                        chip(pair.0, pair.1)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func chip(_ value: Selection, _ label: String) -> some View {
        let selected = value == selection
        return Button {
            selection = value
        } label: {
            Text(label)
                .font(.subheadline.weight(selected ? .semibold : .medium))
                .foregroundStyle(selected ? BlueprintTheme.cream : BlueprintTheme.mutedLight)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    selected ? BlueprintTheme.purple.opacity(0.38) : BlueprintTheme.cardInner
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            selected ? BlueprintTheme.lavender.opacity(0.55) : BlueprintTheme.border,
                            lineWidth: 1
                        )
                )
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Toolbar menu (Progress filters)

/// Capsule `Menu` for navigation bars — same card colors, no default “Sort” text button.
struct BlueprintToolbarMenuPicker<Selection: Hashable>: View {
    let accessibilityLabel: String
    var systemImage: String?
    @Binding var selection: Selection
    let options: [(Selection, String)]

    private var displayText: String {
        options.first { $0.0 == selection }?.1 ?? accessibilityLabel
    }

    var body: some View {
        Menu {
            Picker(accessibilityLabel, selection: $selection) {
                ForEach(options, id: \.0) { pair in
                    Text(pair.1).tag(pair.0)
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(displayText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BlueprintTheme.muted)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BlueprintTheme.cream)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(BlueprintTheme.cardInner)
            .overlay(
                Capsule()
                    .strokeBorder(BlueprintTheme.border, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }
}

// MARK: - Date (compact)

struct BlueprintCompactDatePicker: View {
    var title: String
    @Binding var date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BlueprintTheme.muted)
            DatePicker("", selection: $date, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(BlueprintTheme.lavender)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BlueprintTheme.cardInner)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BlueprintTheme.border, lineWidth: 1)
                )
        }
    }
}
