import SwiftData
import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case general, connect, engine, vault, shortcuts, about

    var label: String {
        switch self {
        case .general: "General"
        case .connect: "Connect"
        case .engine: "Engine"
        case .vault: "Vault"
        case .shortcuts: "Shortcuts"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .connect: "antenna.radiowaves.left.and.right"
        case .engine: "cpu"
        case .vault: "tray"
        case .shortcuts: "command"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var scheme
    @State private var selectedTab: SettingsTab = .general
    @State private var hoveredTab: SettingsTab? = nil
    
    @AppStorage("theme_preference") private var themePreference = 0
    @AppStorage("custom_theme_palette") private var customThemePalette = 0

    var body: some View {
        VStack(spacing: 0) {
            // Floating icon bar
            HStack(spacing: 32) {
                ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(selectedTab == tab ? AppTheme.Colors.accent : .secondary)
                            .frame(width: 44, height: 44)
                            .background {
                                if hoveredTab == tab && selectedTab != tab {
                                    Circle()
                                        .fill(AppTheme.Colors.surfaceSubtle(for: scheme))
                                        .transition(.opacity)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(AppTheme.Colors.accent)
                                        .frame(width: 18, height: 2.5)
                                        .offset(y: 2)
                                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .center)))
                                }
                            }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovered in
                        withAnimation(AppTheme.Animation.easeInOut) {
                            hoveredTab = isHovered ? tab : nil
                        }
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 14)

            Rectangle()
                .fill(AppTheme.Colors.strokeDefault(for: scheme))
                .frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general: GeneralSection()
                    case .connect: ConnectSection()
                    case .engine: EngineSection()
                    case .vault: VaultSection()
                    case .shortcuts: ShortcutsSection()
                    case .about: AboutSection()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .adaptiveBackground()
        .frame(maxWidth: 600, minHeight: 620)
        .fontDesign(.rounded)
        .animation(AppTheme.Animation.springSnappy, value: selectedTab)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsTab)) { notification in
            if let tab = notification.object as? SettingsTab {
                selectedTab = tab
            }
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
}
