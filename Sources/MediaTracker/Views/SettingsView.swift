import SwiftData
import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case general, services, discovery, data, about

    var label: String {
        switch self {
        case .general: "General"
        case .services: "Services"
        case .discovery: "Discovery"
        case .data: "Data"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .services: "antenna.radiowaves.left.and.right"
        case .discovery: "safari"
        case .data: "externaldrive"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var scheme
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Full-width tab bar
            tabBar
                .padding(.top, 20)
                .padding(.bottom, 16)

            Divider()

            // Content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case .general: GeneralSection()
                    case .services: ServicesSection()
                    case .discovery: DiscoverySettingsSection()
                    case .data: DataSection()
                    case .about: AboutSection()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(AppTheme.Colors.background(for: scheme))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(maxWidth: 520, minHeight: 620)
        .fontDesign(.rounded)
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
        .padding(.horizontal, 12)
    }

    private func tabButton(tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(AppTheme.Animation.springSnappy) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24, height: 24)

                Text(tab.label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AppTheme.Colors.accent : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(isSelected ? AppTheme.Colors.accent.opacity(0.08) : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
