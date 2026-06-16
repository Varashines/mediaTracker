import SwiftUI

struct KeyboardShortcutsSection: View {
    @Environment(\.colorScheme) var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            SettingsSectionHeader(text: "Navigation", icon: "command", color: .blue)

            SettingsCard(color: .blue) {
                VStack(spacing: 0) {
                    shortcutRow(key: "1", modifiers: .command, label: "Home", showDivider: true)
                    shortcutRow(key: "2", modifiers: .command, label: "Discover", showDivider: true)
                    shortcutRow(key: "3", modifiers: .command, label: "Upcoming", showDivider: true)
                    shortcutRow(key: "4", modifiers: .command, label: "Library (All)", showDivider: true)
                    shortcutRow(key: "5", modifiers: .command, label: "Movies", showDivider: true)
                    shortcutRow(key: "6", modifiers: .command, label: "TV Shows", showDivider: true)
                    shortcutRow(key: "7", modifiers: .command, label: "Smart Hub", showDivider: true)
                    shortcutRow(key: "F", modifiers: .command, label: "Search", showDivider: true)
                    shortcutRow(key: .escape, modifiers: [], label: "Dismiss / Clear Search", showDivider: false)
                }
            }

            SettingsSectionHeader(text: "Media Actions", icon: "play.rectangle", color: .purple)

            SettingsCard(color: .purple) {
                VStack(spacing: 0) {
                    shortcutRow(key: .space, modifiers: [], label: "Mark Watched / Toggle", showDivider: true)
                    shortcutRow(key: "W", modifiers: [], label: "Cycle Status", showDivider: true)
                    shortcutRow(key: "R", modifiers: .command, label: "Refresh Metadata", showDivider: true)
                    shortcutRow(key: .delete, modifiers: .command, label: "Delete from Library", showDivider: true)
                    shortcutRow(key: "L", modifiers: .command, label: "Add to Collection", showDivider: false)
                }
            }

            SettingsSectionHeader(text: "Search Filters", icon: "line.3.horizontal.decrease.circle", color: .green)

            SettingsCard(color: .green) {
                VStack(spacing: 0) {
                    shortcutRow(key: "1", modifiers: [.command, .option], label: "All Types", showDivider: true)
                    shortcutRow(key: "2", modifiers: [.command, .option], label: "Movies Only", showDivider: true)
                    shortcutRow(key: "3", modifiers: [.command, .option], label: "TV Shows Only", showDivider: false)
                }
            }

            SettingsSectionHeader(text: "General", icon: "gearshape", color: .orange)

            SettingsCard(color: .orange) {
                VStack(spacing: 0) {
                    shortcutRow(key: ",", modifiers: .command, label: "Open Settings", showDivider: true)
                    shortcutRow(key: "Q", modifiers: .command, label: "Quit", showDivider: false)
                }
            }
        }
    }

    // MARK: - Row Builder

    @ViewBuilder
    private func shortcutRow(
        key: KeyEquivalent,
        modifiers: EventModifiers,
        label: String,
        showDivider: Bool
    ) -> some View {
        HStack {
            Text(label)
                .font(AppTheme.Font.body)
                .foregroundStyle(.primary)
            Spacer()
            ShortcutKeyBadge(key: key, modifiers: modifiers)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)

        if showDivider {
            Divider()
                .overlay(AppTheme.Colors.strokeDefault(for: scheme))
                .padding(.leading, 14)
        }
    }
}

// MARK: - Key Badge

private struct ShortcutKeyBadge: View {
    let key: KeyEquivalent
    let modifiers: EventModifiers
    @Environment(\.colorScheme) var scheme

    var body: some View {
        HStack(spacing: 3) {
            if modifiers.contains(.command) {
                keyPill("⌘")
            }
            if modifiers.contains(.option) {
                keyPill("⌥")
            }
            if modifiers.contains(.control) {
                keyPill("⌃")
            }
            if modifiers.contains(.shift) {
                keyPill("⇧")
            }
            keyPill(keyLabel)
        }
    }

    private var keyLabel: String {
        switch key {
        case .space: "Space"
        case .escape: "Esc"
        case .delete: "⌫"
        case .leftArrow: "←"
        case .rightArrow: "→"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .return: "↵"
        case .tab: "⇥"
        default: key.character.uppercased()
        }
    }

    private func keyPill(_ text: String) -> some View {
        Text(text)
            .font(AppTheme.Font.caption)
            .foregroundStyle(.primary)
            .frame(minWidth: 20)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AppTheme.Colors.strokeDefault(for: scheme), lineWidth: 0.5)
            )
    }
}
