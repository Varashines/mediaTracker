import SwiftUI
import SwiftData

struct HomeViewSections: View {
    let homeContinueWatching: [MediaThumbnailMetadata]
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recommendations: [MediaThumbnailMetadata]
    let pickOfTheDay: [MediaThumbnailMetadata]
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onCategorySelected: (NavigationCategory) -> Void
    let onTrendingAdd: ((MediaSearchResult) -> Void)?

    private enum HomeSection {
        case forYou, recentlyWatched, pickOfTheDay, trendingMovies, trendingShows
    }

    @State private var visibleSection: HomeSection? = nil
    @State private var trendingMovies: [MediaSearchResult] = []
    @State private var trendingShows: [MediaSearchResult] = []
    @Namespace private var pillNamespace

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
                if !pickOfTheDay.isEmpty {
                    sectionButton(
                        section: .pickOfTheDay,
                        icon: "star.fill",
                        label: "Pick of the Day",
                        isActive: visibleSection == .pickOfTheDay
                    )
                }
                sectionButton(
                    section: .trendingMovies,
                    icon: "flame.fill",
                    label: "Trending Movies",
                    isActive: visibleSection == .trendingMovies
                )
                sectionButton(
                    section: .trendingShows,
                    icon: "flame.fill",
                    label: "Trending Shows",
                    isActive: visibleSection == .trendingShows
                )
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.pageMargin)

            if visibleSection == .recentlyWatched {
                WatchedThisWeek()
                    .padding(.bottom, AppTheme.Spacing.small)
                    .transition(.opacity)
            }

            if visibleSection == .forYou {
                ForYouCarousel(
                    items: recommendations, namespace: namespace,
                    isFastScrolling: isFastScrolling, onSelect: onSelectHero
                )
                .padding(.bottom, AppTheme.Spacing.small)
                .transition(.opacity)
            }

            if visibleSection == .pickOfTheDay {
                PickOfDayCarousel(
                    items: pickOfTheDay, namespace: namespace,
                    isFastScrolling: isFastScrolling, onSelect: onSelectHero
                )
                .padding(.bottom, AppTheme.Spacing.small)
                .transition(.opacity)
            }

            if visibleSection == .trendingMovies || visibleSection == .trendingShows {
                if visibleSection == .trendingMovies {
                    TrendingCarousel(items: trendingMovies, title: "Trending Movies") { result in
                        onTrendingAdd?(result)
                    }
                    .padding(.bottom, AppTheme.Spacing.small)
                    .transition(.opacity)
                }
                if visibleSection == .trendingShows {
                    TrendingCarousel(items: trendingShows, title: "Trending Shows") { result in
                        onTrendingAdd?(result)
                    }
                    .padding(.bottom, AppTheme.Spacing.small)
                    .transition(.opacity)
                }
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
        .task {
            async let movies = APIClient.shared.fetchTrendingMovies()
            async let shows = APIClient.shared.fetchTrendingTVShows()
            trendingMovies = (try? await movies) ?? []
            trendingShows = (try? await shows) ?? []
        }
    }

    private func sectionButton(section: HomeSection, icon: String, label: String, isActive: Bool) -> some View {
        Button {
            withAnimation(AppTheme.Animation.springSnappy) {
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
                Text(label)
                    .font(AppTheme.Font.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(isActive ? AppTheme.Colors.accent : Color.primary.opacity(0.06))
                    .overlay {
                        if isActive {
                            Capsule()
                                .fill(AppTheme.Colors.accent)
                                .matchedGeometryEffect(id: "homePill", in: pillNamespace)
                        }
                    }
            }
            .foregroundStyle(isActive ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
