import SwiftData
import SwiftUI

enum SettingsTab: Int, CaseIterable {
    case general, connect, engine, vault

    var label: String {
        switch self {
        case .general: "General"
        case .connect: "Connect"
        case .engine: "Engine"
        case .vault: "Vault"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .connect: "antenna.radiowaves.left.and.right"
        case .engine: "cpu"
        case .vault: "tray"
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var scheme
    @Namespace private var tabNamespace
    @State private var selectedTab: SettingsTab = .general
    @State private var hoveredTab: SettingsTab? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack {
                Spacer()
                HStack(spacing: 0) {
                    ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .scaleEffect(selectedTab == tab ? 1.05 : 1.0)
                                Text(tab.label)
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                            .frame(width: 90, height: 50)
                            .background {
                                ZStack {
                                    if selectedTab == tab {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.accentColor.opacity(scheme == .dark ? 0.15 : 0.08))
                                            .matchedGeometryEffect(id: "selected_settings_tab", in: tabNamespace)
                                    } else if hoveredTab == tab {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(Color.primary.opacity(scheme == .dark ? 0.05 : 0.03))
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { isHovered in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                hoveredTab = isHovered ? tab : nil
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(scheme == .dark ? 0.08 : 0.04), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                Spacer()
            }
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().opacity(0.06)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case .general: GeneralSection()
                    case .connect: ConnectSection()
                    case .engine: EngineSection()
                    case .vault: VaultSection()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: 520, minHeight: 640)
        .fontDesign(.rounded)
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
