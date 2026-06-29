import SwiftUI

// MARK: - Card (grouped section)

struct SettingsCard<Content: View>: View {
    var color: Color = .clear
    @ViewBuilder let content: () -> Content

    var body: some View {
        GlassCard(color: color) {
            content()
        }
    }
}

// MARK: - SettingsRow

struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var showDivider: Bool = true
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.colorScheme) var scheme
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
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
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .allowsHitTesting(false)
                        .padding(.horizontal, AppTheme.Spacing.tiny)
                }
            }
            .onHover { hovered in
                withAnimation(AppTheme.Animation.easeInOut) {
                    isHovered = hovered
                }
            }

            if showDivider {
                Rectangle()
                    .fill(AppTheme.Colors.strokeDefault(for: scheme))
                    .frame(height: 1)
                    .padding(.leading, AppTheme.Spacing.medium)
            }
        }
    }
}

// MARK: - SectionHeader

struct SettingsSectionHeader: View {
    let text: String
    var icon: String? = nil
    var color: Color = .primary

    var body: some View {
        HStack(spacing: AppTheme.Spacing.mini) {
            if let icon {
                Image(systemName: icon)
                    .font(AppTheme.Font.caption)
                    .foregroundStyle(color)
            }
            Text(text)
                .font(AppTheme.Font.settingsSectionHeader)
                .foregroundStyle(.primary)
        }
        .padding(.bottom, AppTheme.Spacing.mini)
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
    @Environment(\.colorScheme) private var scheme
    @State private var isHovered = false

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
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .allowsHitTesting(false)
                    .padding(.horizontal, AppTheme.Spacing.tiny)
            }
        }
        .onHover { hovered in
            withAnimation(AppTheme.Animation.easeInOut) {
                isHovered = hovered
            }
        }
        .overlay(alignment: .bottom) {
            if showDivider {
                Rectangle()
                    .fill(AppTheme.Colors.strokeDefault(for: scheme))
                    .frame(height: 1)
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
