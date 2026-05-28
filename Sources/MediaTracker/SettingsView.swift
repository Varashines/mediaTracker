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
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack {
                Spacer()
                HStack(spacing: 0) {
                    ForEach(SettingsTab.allCases, id: \.rawValue) { tab in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 15, weight: .medium))
                                Text(tab.label)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                            }
                            .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                            .frame(width: 90, height: 52)
                            .background {
                                if selectedTab == tab {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }
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
                .padding(.horizontal, 28)
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
