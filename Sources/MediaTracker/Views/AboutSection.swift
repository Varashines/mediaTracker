import SwiftUI

struct AboutSection: View {
    @Environment(\.colorScheme) var scheme

    private var appVersion: String {
        "7.1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xLarge) {
            SettingsCard {
                VStack(spacing: AppTheme.Spacing.smallMedium) {
                    HStack(spacing: AppTheme.Spacing.smallMedium) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                            Text("MediaTracker")
                                .font(AppTheme.Font.titleMedium)
                            Text("Version \(appVersion) (\(buildNumber))")
                                .font(AppTheme.Font.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Track movies and TV shows you've watched, discover what to watch next, and keep your viewing history organized.")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(AppTheme.Spacing.micro)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
