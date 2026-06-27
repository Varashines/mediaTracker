import SwiftUI

struct WatchProvidersView: View {
    let providers: [WatchProviderResult]
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.medium) {
                ForEach(providers) { provider in
                    ProviderCard(provider: provider, colorScheme: colorScheme)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct ProviderCard: View {
    let provider: WatchProviderResult
    let colorScheme: ColorScheme

    var body: some View {
        VStack(spacing: 6) {
            CachedImage(
                url: provider.logoURL.flatMap(URL.init(string:)),
                targetSize: CGSize(width: 45, height: 45),
                priority: .normal
            ) {
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 45, height: 45)
            }
            .frame(width: 45, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.medium))

            Text(provider.name)
                .font(AppTheme.Font.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
    }
}
