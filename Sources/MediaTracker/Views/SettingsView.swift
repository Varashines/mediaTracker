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
    @State private var hoveredTab: SettingsTab? = nil
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: 520, minHeight: 620)
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
        HStack(spacing: AppTheme.Spacing.small) {
            ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                tabButton(tab: tab)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xLarge)
        .frame(maxWidth: .infinity)
    }

    private func tabButton(tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        let isHovered = hoveredTab == tab

        return Button {
            if AppThemeCoordinator.isReducingVisualEffects {
                selectedTab = tab
            } else {
                withAnimation(AppTheme.Animation.springSnappy) {
                    selectedTab = tab
                }
            }
        } label: {
            Image(systemName: isSelected ? tab.fillIcon : tab.icon)
                .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? AppTheme.Colors.accent : (isHovered ? Color.primary.opacity(0.5) : .secondary))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AppThemeCoordinator.isReducingVisualEffects
                        ? AnyShapeStyle(AppTheme.Colors.background(for: scheme))
                        : AnyShapeStyle(.ultraThinMaterial))
                    .if(!AppThemeCoordinator.isReducingVisualEffects) { view in
                        view.overlay(
                            Capsule()
                                .stroke(isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                    }
            )
            .clipShape(Capsule())
            .if(!AppThemeCoordinator.isReducingVisualEffects) { view in
                view.overlay(
                    Group {
                        if isSelected {
                            Capsule()
                                .fill(AppTheme.Colors.accent.opacity(0.18))
                                .matchedGeometryEffect(id: "settings_tab", in: tabNamespace)
                        }
                    }
                )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if AppThemeCoordinator.isReducingVisualEffects {
                hoveredTab = hovering ? tab : nil
            } else {
                withAnimation(AppTheme.Animation.microInteraction) {
                    hoveredTab = hovering ? tab : nil
                }
            }
        }
        .accessibilityLabel(tab.label)
    }
}
