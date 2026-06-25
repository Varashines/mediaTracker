import SwiftData
import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case general, services, discovery, data, shortcuts, about

    var label: String {
        switch self {
        case .general: "General"
        case .services: "Services"
        case .discovery: "Discovery"
        case .data: "Data"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .services: "antenna.radiowaves.left.and.right"
        case .discovery: "safari"
        case .data: "externaldrive"
        case .shortcuts: "command"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var scheme
    @State private var selectedTab: SettingsTab = .general
    @Namespace private var tabNamespace

    var body: some View {
        VStack(spacing: 0) {
            tabBar
                .padding(.top, AppTheme.Spacing.large)
                .padding(.bottom, AppTheme.Spacing.medium)

            Divider()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .general: GeneralSection()
                    case .services: ServicesSection()
                    case .discovery: DiscoverySettingsSection()
                    case .data: DataSection()
                    case .shortcuts: KeyboardShortcutsSection()
                    case .about: AboutSection()
                    }
                }
                .transition(.opacity.combined(with: .scale(0.98)))
                .padding(.horizontal, AppTheme.Spacing.xLarge)
                .padding(.vertical, AppTheme.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(.ultraThinMaterial)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: 520, minHeight: 620)
        .animation(AppTheme.Animation.springSnappy, value: selectedTab)
        .onAppear {
            Task {
                guard let aliases = UserDefaults.standard.string(forKey: "studio_aliases"),
                    !aliases.isEmpty
                else { return }
                StudioAliasManagerView.migrateLegacyAliases(
                    from: aliases, into: modelContext.container)
                await MainActor.run { UserDefaults.standard.removeObject(forKey: "studio_aliases") }
            }
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                tabButton(tab: tab)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.small)
    }

    private func tabButton(tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: AppTheme.Spacing.mini) {
                Image(systemName: tab.icon)
                    .font(AppTheme.Font.settingsIcon)
                    .frame(width: AppTheme.Spacing.large, height: AppTheme.Spacing.large)

                Text(tab.label)
                    .font(AppTheme.Font.label)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.compact)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                        .fill(AppTheme.Colors.accent.opacity(0.08))
                        .matchedGeometryEffect(id: "settings_tab", in: tabNamespace)
                }
            }
            .contentShape(Rectangle())
            .accessibilityLabel(tab.label)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering && !isSelected {
                // subtle hover fill is handled via animated state would require @State per tab
                // instead we let the native button style handle press feedback
            }
        }
    }
}
