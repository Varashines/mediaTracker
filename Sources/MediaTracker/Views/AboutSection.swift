import SwiftUI

struct AboutSection: View {
    @Environment(\.colorScheme) var scheme

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    /// Codename for this release line (v9 = "Arc").
    private var codename: String { "Arc" }

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
                            Text("Version \(appVersion) — \"\(codename)\"")
                                .font(AppTheme.Font.label)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Track movies and TV shows you've watched, discover what to watch next, and keep your viewing history organized.")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(AppTheme.Spacing.micro)

                    Divider()
                        .padding(.vertical, AppTheme.Spacing.small)

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.smallMedium) {
                        Label("Data & Credits", systemImage: "books.vertical.fill")
                            .font(AppTheme.Font.bodyMedium)
                            .foregroundStyle(.primary)

                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .font(AppTheme.Font.label)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: AppTheme.Spacing.small) {
                            Link(destination: URL(string: "https://www.themoviedb.org")!) {
                                Text("TMDB")
                                    .font(AppTheme.Font.label)
                                    .foregroundStyle(AppTheme.Colors.accent)
                            }
                            Link(destination: URL(string: "https://www.omdbapi.com")!) {
                                Text("OMDb")
                                    .font(AppTheme.Font.label)
                                    .foregroundStyle(AppTheme.Colors.accent)
                            }
                            Link(destination: URL(string: "https://www.tvmaze.com")!) {
                                Text("TVMaze")
                                    .font(AppTheme.Font.label)
                                    .foregroundStyle(AppTheme.Colors.accent)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
