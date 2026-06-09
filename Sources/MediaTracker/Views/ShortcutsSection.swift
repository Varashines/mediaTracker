import SwiftUI

struct ShortcutsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Keyboard Shortcuts", icon: "command", color: .orange)
            SettingsCard(color: .orange) {
                VStack(alignment: .leading, spacing: 0) {
                    shortcutRow(keys: ["⌘", "←"], title: "Go Back", subtitle: "Navigate to previous view")
                    shortcutRow(keys: ["⌘", "F"], title: "Search", subtitle: "Open the search bar")
                    shortcutRow(keys: ["⌘", "R"], title: "Refresh", subtitle: "Sync library metadata", showDivider: false)
                }
            }

            SettingsSectionHeader(text: "Quick Navigation", icon: "sidebar.left", color: .teal)
            SettingsCard(color: .teal) {
                VStack(alignment: .leading, spacing: 0) {
                    shortcutRow(keys: ["⌘", "1"], title: "Home", subtitle: "Go to home screen")
                    shortcutRow(keys: ["⌘", "2"], title: "Discovery", subtitle: "Open discovery hub")
                    shortcutRow(keys: ["⌘", "3"], title: "Upcoming", subtitle: "Open release calendar")
                    shortcutRow(keys: ["⌘", "4"], title: "Library", subtitle: "Show all items")
                    shortcutRow(keys: ["⌘", "5"], title: "Movies", subtitle: "Filter movies only")
                    shortcutRow(keys: ["⌘", "6"], title: "TV Shows", subtitle: "Filter TV shows only")
                    shortcutRow(keys: ["⌘", "7"], title: "Smart Hub", subtitle: "Open smart hub", showDivider: false)
                }
            }

            SettingsSectionHeader(text: "Detail View", icon: "list.bullet", color: .indigo)
            SettingsCard(color: .indigo) {
                VStack(alignment: .leading, spacing: 0) {
                    shortcutRow(keys: ["Space"], title: "Mark Watched", subtitle: "TV: next episode · Movie: toggle", showDivider: true)
                    shortcutRow(keys: ["W"], title: "Cycle Status", subtitle: "Rotate through available states", showDivider: true)
                    shortcutRow(keys: ["⌘", "L"], title: "Add to Collection", subtitle: "Open collection picker", showDivider: true)
                    shortcutRow(keys: ["⌘", "⌫"], title: "Delete", subtitle: "Remove from library", showDivider: false)
                }
            }

            SettingsSectionHeader(text: "General", icon: "arrow.left.circle", color: .purple)
            SettingsCard(color: .purple) {
                VStack(alignment: .leading, spacing: 0) {
                    shortcutRow(keys: ["Esc"], title: "Dismiss", subtitle: "Clear search or close sheet", showDivider: false)
                }
            }
        }
    }

    private func shortcutRow(keys: [String], title: String, subtitle: String, showDivider: Bool = true) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    ForEach(keys, id: \.self) { key in
                        Text(key)
                            .font(AppTheme.Font.caption)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(title)
                        .font(AppTheme.Font.settingsRowTitle)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AppTheme.Font.settingsSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)

            if showDivider {
                Rectangle()
                    .fill(AppTheme.Colors.strokeDefault(for: ColorScheme.light))
                    .frame(height: 1)
                    .padding(.leading, AppTheme.Spacing.medium)
            }
        }
    }
}
