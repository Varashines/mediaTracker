import SwiftUI

struct EngineSection: View {
    @AppStorage("skip_startup_background_tasks") private var skipStartupTasks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSectionHeader(text: "Data Processing", icon: "cpu", color: .teal)
            SettingsCard(color: .teal) {
                StudioAliasManagerView()
                Rectangle()
                    .fill(AppTheme.Colors.strokeDefault(for: scheme))
                    .frame(height: 1)
                    .padding(.leading, 16)
                DiscoveryManagementView()
            }

            SettingsSectionHeader(text: "Startup", icon: "power", color: .orange)
            SettingsCard(color: .orange) {
                SettingsToggleRow(title: "Skip Background Tasks", subtitle: "Disable automatic metadata repair on launch", showDivider: false, isOn: $skipStartupTasks)
            }
        }
    }

    @Environment(\.colorScheme) var scheme
}
