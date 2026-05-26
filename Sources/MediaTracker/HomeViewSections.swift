import SwiftUI
import SwiftData

struct HomeViewSections: View {
    let homeContinueWatching: [MediaThumbnailMetadata]
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recommendations: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onCategorySelected: (NavigationCategory) -> Void

    @State private var showWatchedThisWeek = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // 0. RECENTLY WATCHED TOGGLE
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        showWatchedThisWeek.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 10))
                        Text(showWatchedThisWeek ? "Hide Recently Watched" : "Recently Watched")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.trailing, AppTheme.Spacing.pageMargin)
            }

            if showWatchedThisWeek {
                WatchedThisWeek()
                    .padding(.bottom, AppTheme.Spacing.small)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 1. CONTINUE WATCHING
            ContinueWatchingCarousel(
                items: homeContinueWatching, namespace: namespace,
                isFastScrolling: isFastScrolling, onSelect: onSelectHero
            ) {
                onCategorySelected(.discover)
            }
            .padding(.top, AppTheme.Spacing.small)
            .padding(.bottom, AppTheme.Spacing.small)

            // 2. COMING SOON (Limited to 10)
            let comingSoon = featuredCarouselItems.isEmpty ? (groupedItems.first(where: { $0.0 == "Coming Soon" })?.1 ?? []) : featuredCarouselItems
            if !comingSoon.isEmpty {
                FeaturedUpcomingCarousel(
                    items: Array(comingSoon.prefix(10)), namespace: namespace,
                    isFastScrolling: isFastScrolling, onSelect: onSelectHero
                )
                .padding(.bottom, AppTheme.Spacing.small)
            }

            // 3. FOR YOU (Recommendations)
            ForYouCarousel(
                items: recommendations, namespace: namespace,
                isFastScrolling: isFastScrolling, onSelect: onSelectHero
            )
            .padding(.bottom, AppTheme.Spacing.small)
        }
    }
}
