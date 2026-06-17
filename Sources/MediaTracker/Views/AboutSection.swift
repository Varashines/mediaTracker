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
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("MediaTracker")
                            .font(AppTheme.Font.titleMedium)
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(AppTheme.Font.label)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Track movies and TV shows you've watched, discover what to watch next, and keep your viewing history organized.")
                    .font(AppTheme.Font.label)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.Colors.cardFill(for: scheme))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .stroke(AppTheme.Colors.strokeDefault(for: scheme), lineWidth: 0.5)
            )
        }
    }
}
