import SwiftData
import SwiftUI

struct DiscoverySettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(UserDefaultsKeys.discoveryAutoSync.rawValue) private var discoveryAutoSync = false
    @State private var showClearCacheConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
            SettingsCard(color: .indigo) {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Auto-sync Discovery",
                        subtitle: "Refresh studios, networks, and genres when the app wakes from sleep",
                        showDivider: true,
                        isOn: $discoveryAutoSync
                    )
                    SettingsRow(title: "Clear Discovery Cache", subtitle: "Reset cached hub data and refresh from TMDB", showDivider: false) {
                        SettingsButton(title: "Clear") {
                            showClearCacheConfirmation = true
                        }
                    }
                }
            }

            SettingsCard(color: .teal) {
                StudioAliasManagerView()
            }

            SettingsCard(color: .orange) {
                DiscoveryManagementView()
            }
        }
        .confirmationDialog("Clear Discovery Cache?", isPresented: $showClearCacheConfirmation) {
            Button("Clear & Refresh") {
                let container = modelContext.container
                NetworkThemeManager.shared.resetAll()
                ImageCache.shared.clearFullCache()
                Task {
                    let sync = DiscoverySyncService(modelContainer: container)
                    await sync.syncLibrary(force: true)
                    MediaStateService.shared.requestDiscoveryResync()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear cached discovery data and re-fetch from TMDB. It may take a moment.")
        }
    }
}
