import SwiftUI
import SwiftData

struct ForYouCarousel: View {
    let items: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelect: (MediaThumbnailMetadata) -> Void
    /// False once a fetch has settled — distinguishes loading skeletons
    /// from a genuine empty state.
    var isLoading: Bool = true
    var onDiscover: (() -> Void)? = nil

    var body: some View {
        HomeCarouselSection(
            title: "For You",
            icon: "sparkles",
            iconColor: .yellow,
            scrollSpace: "FY_Scroll",
            items: items,
            spacing: AppTheme.Spacing.smallMedium,
            onSelect: onSelect,
            emptyContent: {
                if isLoading {
                    // Cards-only: HomeCarouselSection already renders the real
                    // header above. Geometry (360x180, same gaps/paddings) and
                    // shimmer match the loaded row so cards swap in with no
                    // layout jump.
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.smallMedium) {
                            ForEach(0..<3, id: \.self) { _ in
                                ForYouCardSkeleton()
                            }
                        }
                        .padding(.horizontal, AppTheme.Spacing.pageMargin)
                        .padding(.vertical, AppTheme.Spacing.medium - 1)
                    }
                    .scrollClipDisabled()
                } else {
                    emptyStateCta
                }
            }
        ) { metadata, fast in
            let index = items.firstIndex(where: { $0.id == metadata.id })
            return ForYouCompactCard(
                metadata: metadata,
                isFastScrolling: isFastScrolling || fast,
                staggerIndex: index
            )
        }
    }

    private var emptyStateCta: some View {
        Button {
            onDiscover?()
        } label: {
            HStack(spacing: AppTheme.Spacing.medium) {
                Image(systemName: "wand.and.stars")
                    .font(AppTheme.Font.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, height: 54)
                    .background(.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.small))

                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                    Text("No picks yet")
                        .font(AppTheme.Font.title3)
                        .foregroundStyle(.primary)
                    Text("Rate titles and grow your Wishlist to get personal picks.")
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

// MARK: - Geometry-Matched Skeleton Placeholder

private struct ForYouCardSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.appleTV, style: .continuous)
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
                RoundedRectangle(cornerRadius: AppTheme.Radius.small, style: .continuous)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 100, height: 150)
                    .padding(.leading, 14)
                    .padding(.vertical, 14)

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
        .frame(width: 360, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.appleTV, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.Radius.appleTV, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
        }
        .shimmering()
    }
}
