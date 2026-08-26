import SwiftUI
import SwiftData

struct ForYouCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void

    var body: some View {
        HomeCarouselSection(
            title: "For You",
            icon: "sparkles",
            iconColor: .yellow,
            scrollSpace: "FY_Scroll",
            items: items,
            onSelect: onSelect,
            emptyContent: {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.large) {
                        ForEach(0..<3, id: \.self) { _ in
                            ForYouCardSkeleton()
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.pageMargin)
                    .padding(.vertical, AppTheme.Spacing.medium - 1)
                }
                .scrollClipDisabled()
            }
        ) { metadata, fast in
            ForYouCompactCard(metadata: metadata, isFastScrolling: isFastScrolling || fast)
        }
    }
}

// MARK: - Geometry-Matched Skeleton Placeholder

private struct ForYouCardSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.08 : 0.05))

            // Top-right pill skeleton
            VStack {
                HStack {
                    Spacer()
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 130, height: 22)
                        .padding(12)
                }
                Spacer()
            }

            HStack(spacing: 16) {
                // Poster skeleton
                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 110, height: 160)
                    .padding(.leading, 16)
                    .padding(.vertical, 16)

                // Info pane skeleton
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 160, height: 22)

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: 100, height: 14)
                }
                .padding(.vertical, 20)

                Spacer(minLength: 0)
            }
        }
        .frame(width: 420, height: 200)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.large, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
        .shimmering()
    }
}
