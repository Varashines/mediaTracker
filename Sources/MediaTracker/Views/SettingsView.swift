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

    var fillIcon: String {
        switch self {
        case .general: "gearshape.fill"
        case .services: "antenna.radiowaves.left.and.right"
        case .discovery: "safari.fill"
        case .data: "externaldrive.fill"
        case .shortcuts: "command.circle.fill"
        case .about: "info.circle.fill"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var scheme
    @State private var selectedTab: SettingsTab = .general

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
                .if(!AppThemeCoordinator.isReducingVisualEffects) {
                    $0.transition(.opacity.combined(with: .scale(0.98)))
                }
                .padding(.horizontal, AppTheme.Spacing.xLarge)
                .padding(.vertical, AppTheme.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(AppThemeCoordinator.isReducingVisualEffects
            ? AnyShapeStyle(AppTheme.Colors.background(for: scheme))
            : AnyShapeStyle(.ultraThinMaterial))
        .frame(
            minWidth: AppTheme.Layout.settingsMinimumWidth,
            idealWidth: AppTheme.Layout.settingsIdealWidth,
            maxWidth: AppTheme.Layout.settingsMaximumWidth,
            minHeight: 640,
            idealHeight: AppTheme.Layout.settingsIdealHeight
        )
        .if(!AppThemeCoordinator.isReducingVisualEffects) {
            $0.animation(AppTheme.Animation.springSnappy, value: selectedTab)
        }
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
        SegmentedPillControl(
            options: SettingsTab.allCases,
            selection: $selectedTab
        ) { tab, isSelected in
            HStack(spacing: AppTheme.Spacing.micro) {
                Image(systemName: isSelected ? tab.fillIcon : tab.icon)
                    .font(.system(size: 11, weight: .bold))

                Text(tab.label)
                    .font(AppTheme.Font.bodyBold)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.smallMedium)
    }
}
