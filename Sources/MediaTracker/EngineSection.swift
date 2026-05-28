import SwiftUI

struct EngineSection: View {
    @AppStorage("skip_startup_background_tasks") private var skipStartupTasks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Data Processing", color: .teal)
            SettingsCard(color: .teal) {
                StudioAliasManagerView()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            SettingsCard(color: .teal) {
                DiscoveryManagementView()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            SettingsSectionHeader(text: "Startup", color: .orange)
            SettingsCard(color: .orange) {
                SettingsToggleRow(title: "Skip Background Tasks", subtitle: "Disable automatic metadata repair on launch", showDivider: false, isOn: $skipStartupTasks)
            }
        }
    }
}
