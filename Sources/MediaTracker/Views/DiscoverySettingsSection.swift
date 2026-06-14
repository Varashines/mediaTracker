import SwiftUI

struct DiscoverySettingsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            SettingsSectionHeader(text: "Studio Aliases", icon: "person.3.fill", color: .teal)

            SettingsCard(color: .teal) {
                StudioAliasManagerView()
            }

            SettingsSectionHeader(text: "Hidden Networks", icon: "eye.slash", color: .orange)

            SettingsCard(color: .orange) {
                DiscoveryManagementView()
            }
        }
    }
}
