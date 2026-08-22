import SwiftUI

// MARK: - Cute Group (replaces GlassCard for Settings)

/// Soft grouped section — cute & polished, no hover wash.
/// Used by all Settings sections after the sidebar redesign.
struct SettingsGroup<Content: View>: View {
    var header: String? = nil
    var color: Color = .clear
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
            if let header {
                Text(header)
                    .font(AppTheme.Font.settingsSectionHeader)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppTheme.Spacing.mini)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(AppTheme.Colors.cardFill(for: scheme), in: RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .stroke(
                        color == .clear ? AppTheme.Colors.strokeDefault(for: scheme) : color.opacity(scheme == .dark ? 0.22 : 0.14),
                        lineWidth: 0.6
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
        }
    }
}

// Backwards-compat: old SettingsCard now just wraps SettingsGroup with ultraThinMaterial removed.
struct SettingsCard<Content: View>: View {
    var color: Color = .clear
    @ViewBuilder let content: () -> Content

    var body: some View {
        SettingsGroup(header: nil, color: color) {
            content()
        }
    }
}

// MARK: - Segmented Pill Control

struct SegmentedPillControl<Option: Hashable, Label: View>: View {
    let options: [Option]
    @Binding var selection: Option
    @ViewBuilder let label: (Option, Bool) -> Label

    @Environment(\.colorScheme) private var scheme
    @Namespace private var selectionNamespace
    @State private var hoveredOption: Option?

    var body: some View {
        HStack(spacing: AppTheme.Spacing.micro) {
            ForEach(options, id: \.self) { option in
                let isSelected = selection == option
                let isHovered = hoveredOption == option

                Button {
                    if AppThemeCoordinator.isReducingVisualEffects {
                        selection = option
                    } else {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            selection = option
                        }
                    }
                } label: {
                    label(option, isSelected)
                        .foregroundStyle(
                            isSelected
                                ? AppTheme.Colors.accent
                                : (isHovered ? Color.primary : Color.secondary)
                        )
                        .padding(.horizontal, AppTheme.Spacing.compact)
                        .padding(.vertical, AppTheme.Spacing.mini)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(AppTheme.Colors.accent.opacity(0.18))
                                    .matchedGeometryEffect(id: "segmented_selection", in: selectionNamespace)
                            } else if isHovered {
                                Capsule()
                                    .fill(AppTheme.Colors.surfaceSubtle(for: scheme))
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(AppTheme.Animation.microInteraction) {
                        hoveredOption = hovering ? option : nil
                    }
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(AppTheme.Spacing.micro)
        .background(AppTheme.Colors.cardFill(for: scheme), in: Capsule())
        .overlay {
            Capsule()
                .stroke(AppTheme.Colors.strokeDefault(for: scheme), lineWidth: 0.5)
        }
    }
}

// MARK: - SettingsRow (flat — no hover wash, divider only)

struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTheme.Font.settingsRowTitle)
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTheme.Font.settingsSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showDivider {
                Divider()
                    .padding(.leading, AppTheme.Spacing.medium)
            }
        }
    }
}

// MARK: - SettingsToggleRow

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, showDivider: showDivider) {
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}

// MARK: - SettingsLabeledRow
//
// Use this instead of `SettingsRow` whenever the trailing control is a `Picker`,
// `DatePicker`, `Stepper`, or `Slider`. Those controls expand to the trailing edge
// and squeeze the label horizontally. This variant stacks the title above the control
// so the label can never wrap or clip, per the design rules in AGENTS.md.

struct SettingsLabeledRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.tiny) {
            if let subtitle {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Font.settingsRowTitle)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AppTheme.Font.settingsSubtitle)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(title)
                    .font(AppTheme.Font.settingsRowTitle)
                    .foregroundStyle(.primary)
            }
            HStack {
                trailing()
                Spacer()
            }
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if showDivider {
                Divider()
                    .padding(.leading, AppTheme.Spacing.medium)
            }
        }
    }
}

// MARK: - SettingsButton

struct SettingsButton: View {
    let title: String
    var color: Color = .secondary
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.Font.caption)
                .foregroundStyle(color)
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.micro)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .stroke(color.opacity(isHovered ? 0.3 : 0.15), lineWidth: 0.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .animation(AppTheme.Animation.springSnappy, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - StatusBadge

struct StatusBadge: View {
    let text: String
    let isActive: Bool
    @Environment(\.colorScheme) var colorScheme

    private var activeColor: Color {
        AppTheme.Colors.statusWatched(for: colorScheme)
    }

    private var inactiveColor: Color {
        Color.red
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.mini) {
            Circle()
                .fill(isActive ? activeColor : inactiveColor)
                .frame(width: AppTheme.Spacing.mini, height: AppTheme.Spacing.mini)
            Text(text)
                .font(AppTheme.Font.caption2)
                .foregroundStyle(isActive ? activeColor : inactiveColor)
        }
        .padding(.horizontal, AppTheme.Spacing.tiny)
        .padding(.vertical, AppTheme.Spacing.micro)
        .background((isActive ? activeColor : inactiveColor).opacity(0.08))
        .clipShape(Capsule())
    }
}
