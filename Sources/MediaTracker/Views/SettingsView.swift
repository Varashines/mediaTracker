import SwiftData
import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    @Namespace private var selectionNS

    var body: some View {
        VStack(spacing: 0) {
            topBar
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
            if let raw = UserDefaults.standard.string(forKey: "settings_open_tab"),
               let tab = SettingsTab(rawValue: Int(raw) ?? 0) {
                selectedTab = tab
                UserDefaults.standard.removeObject(forKey: "settings_open_tab")
            }
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

    // MARK: - Cute Top Bar (polished, no sidebar)

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            topBarPills
                .frame(maxWidth: .infinity)
            ScrollView(.horizontal, showsIndicators: false) {
                topBarPills
            }
        }
        .padding(.horizontal, AppTheme.Spacing.smallMedium)
    }

    private var topBarPills: some View {
        HStack(spacing: AppTheme.Spacing.micro) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    if AppThemeCoordinator.isReducingVisualEffects {
                        selectedTab = tab
                    } else {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.Spacing.micro) {
                        ZStack {
                            Circle()
                                .fill(tint(for: tab).opacity(isSelected ? 0.18 : 0.10))
                            Image(systemName: isSelected ? tab.fillIcon : tab.icon)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(tint(for: tab))
                        }
                        .frame(width: 22, height: 22)
                        // Label only on the selected tab — six full pills
                        // overflow the 560pt window and force a scroll view.
                        if isSelected {
                            Text(tab.label)
                                .font(AppTheme.Font.bodyBold)
                                .lineLimit(1)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, AppTheme.Spacing.compact)
                    .padding(.vertical, AppTheme.Spacing.mini)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(tint(for: tab).opacity(0.14))
                                .matchedGeometryEffect(id: "settingsSelection", in: selectionNS)
                        }
                    }
                    .contentShape(Capsule())
                    .help(isSelected ? "" : tab.label)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.Spacing.micro)
        .background(AppTheme.Colors.cardFill(for: scheme), in: Capsule())
        .overlay {
            Capsule()
                .stroke(AppTheme.Colors.strokeDefault(for: scheme), lineWidth: 0.5)
        }
    }

    private func tint(for tab: SettingsTab) -> Color {
        switch tab {
        case .general: return AppTheme.Colors.accent
        case .services: return Color.fromOKLCH(l: 0.65, c: 0.18, h: 145)
        case .discovery: return Color.fromOKLCH(l: 0.60, c: 0.15, h: 265)
        case .data: return Color.fromOKLCH(l: 0.65, c: 0.16, h: 35)
        case .shortcuts: return Color.fromOKLCH(l: 0.60, c: 0.12, h: 285)
        case .about: return Color.secondary
        }
    }
}
