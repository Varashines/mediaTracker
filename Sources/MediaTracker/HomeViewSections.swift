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
    
    var body: some View {
        Group {
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
