import SwiftData
import SwiftUI

struct ContinueWatchingCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void
    var onDiscoverySpotlight: (() -> Void)?

    var body: some View {
        HomeCarouselSection(
            title: "Continue Watching",
            icon: "play.fill",
            iconColor: .blue,
            scrollSpace: "CW_Scroll",
            items: items,
            showsScrollProgress: items.count > 1,
            onSelect: onSelect,
            emptyContent: {
                discoverySpotlightCta
            }
        ) { metadata, fast in
            ContinueWatchingBackdropCard(
                metadata: metadata,
                isFastScrolling: isFastScrolling || fast)
        }
    }

    private var discoverySpotlightCta: some View {
        Button {
            onDiscoverySpotlight?()
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: "sparkles.tv.fill")
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, height: 54)
                    .background(.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))

                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    Text("Ready to start watching?")
                       .font(AppTheme.Font.title3)
                        .foregroundStyle(.primary)
                    Text("Explore the Discovery Hub to find your next favorite show.")
                        .font(AppTheme.Font.body)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(AppTheme.Spacing.medium)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .fill(.thinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppTheme.Spacing.pageMargin)
        .padding(.vertical, AppTheme.Spacing.medium - 1)
    }
}
