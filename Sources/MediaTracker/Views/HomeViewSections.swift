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

    private enum HomeSection {
        case forYou, recentlyWatched
    }

    @State private var visibleSection: HomeSection? = nil

    var body: some View {
        LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            // 0. SECTION TOGGLES
            HStack(spacing: 8) {
                Spacer()
                sectionButton(
                    section: .forYou,
                    icon: "sparkles",
                    label: "For You",
                    isActive: visibleSection == .forYou
                )
                sectionButton(
                    section: .recentlyWatched,
                    icon: "clock.fill",
                    label: "Recently Watched",
                    isActive: visibleSection == .recentlyWatched
                )
                .padding(.trailing, AppTheme.Spacing.pageMargin)
            }

            if visibleSection == .recentlyWatched {
                WatchedThisWeek()
                    .padding(.bottom, AppTheme.Spacing.small)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if visibleSection == .forYou {
                ForYouCarousel(
                    items: recommendations, namespace: namespace,
                    isFastScrolling: isFastScrolling, onSelect: onSelectHero
                )
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
        }
        .padding(.top, AppTheme.Spacing.medium)
    }

    private func sectionButton(section: HomeSection, icon: String, label: String, isActive: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                if visibleSection == section {
                    visibleSection = nil
                } else {
                    visibleSection = section
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(AppTheme.Font.caption2)
                Text(isActive ? "Hide \(label)" : label)
                    .font(AppTheme.Font.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
