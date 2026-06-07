import SwiftData
import SwiftUI

struct ContinueWatchingCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void
    var onDiscoverySpotlight: (() -> Void)?

    @State private var scrollProgress: Double = 0
    private let scrollSpace = "CW_Scroll"

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            SectionHeader(
                title: "Continue Watching",
                icon: "play.fill",
                iconColor: .blue,
                scrollProgress: items.count > 1 ? scrollProgress : nil
            )

            if !items.isEmpty {
                ScrollingHStack(space: scrollSpace, scrollProgress: $scrollProgress) {
                    ForEach(items) { metadata in
                        Button { onSelect(metadata) } label: {
                            MediaThumbnailView(
                                metadata: metadata, mode: .hero, namespace: namespace,
                                isFastScrolling: isFastScrolling)
                        }
                        .buttonStyle(.interactive)
                    }
                }
                .onAppear { prewarm(items: items) }
                .onChange(of: items) { _, newItems in prewarm(items: newItems) }
            } else {
                Button {
                    onDiscoverySpotlight?()
                } label: {
                    HStack(spacing: AppTheme.Spacing.medium) {
                        Image(systemName: "sparkles.tv.fill")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.accent)
                            .frame(width: 54, height: 54)
                            .background(AppTheme.Colors.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))

                        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                            Text("Ready to start watching?")
                               .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Explore the Discovery Hub to find your next favorite show.")
                                .font(.system(size: 13, weight: .regular, design: .rounded))
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
                }
                .buttonStyle(.plain)
                .padding(.horizontal, AppTheme.Spacing.pageMargin)
                .padding(.vertical, AppTheme.Spacing.medium - 1)
            }
        }
        .compositingGroup()
    }

    private func prewarm(items: [MediaThumbnailMetadata]) {
        let urls = items.prefix(10).compactMap { $0.posterURL }.compactMap { URL(string: $0) }
        if !urls.isEmpty {
            ImageCache.shared.prewarmImages(urls: urls, targetSize: .thumbMedium, priority: .normal)
        }
    }
}
