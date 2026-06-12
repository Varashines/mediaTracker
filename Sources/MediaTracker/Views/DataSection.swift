import SwiftUI
import SwiftData

struct DataSection: View {
    @Environment(\.colorScheme) var scheme

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
        }
    }
}
