import SwiftData
import SwiftUI

struct MainLibraryView: View {
    let items: [MediaThumbnailMetadata]
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let homeContinueWatching: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recommendations: [MediaThumbnailMetadata]
    let pickOfTheDay: [MediaThumbnailMetadata]
    let selectedCategory: NavigationCategory
    let searchText: String
    let selectedNetworks: [String]?
    let namespace: Namespace.ID
    @Binding var isFastScrolling: Bool
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onNetworkSelected: ([String]) -> Void
    let onCategorySelected: (NavigationCategory) -> Void
    let onBack: (() -> Void)?
    let onLoadMore: () -> Void
    let onTrendingAdd: ((MediaSearchResult) -> Void)?
    var viewModel: MediaViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var scrollTask: Task<Void, Never>?

    var isCategoryPage: Bool {
        return selectedCategory == .movie || selectedCategory == .tvShow
    }

    var body: some View {
        let columns: [GridItem] = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

        VStack(spacing: 0) {
            if selectedCategory != .home && !(viewModel.collection.selectedCollectionID != nil || selectedCategory.isSmartCategory) {
                if let networks = selectedNetworks, !networks.isEmpty {
                    LibraryHeaderView(
                        selectedCategory: selectedCategory,
                        selectedNetworks: networks, isCategoryPage: isCategoryPage,
                        onNetworkSelected: onNetworkSelected, onBack: onBack,
                        viewModel: viewModel)
                }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    if selectedCategory == .home && searchText.isEmpty && selectedNetworks == nil {
                        HomeViewSections(
                            homeContinueWatching: homeContinueWatching,
                            featuredCarouselItems: featuredCarouselItems,
                            groupedItems: groupedItems,
                            recommendations: recommendations,
                            pickOfTheDay: pickOfTheDay,
                            trendingMovies: viewModel.trendingMovies,
                            trendingShows: viewModel.trendingShows,
                            namespace: namespace,
                            isFastScrolling: isFastScrolling,
                            onSelectHero: onSelectHero,
                            onCategorySelected: onCategorySelected,
                            onTrendingAdd: onTrendingAdd
                        )
                        .transition(.opacity)
                    }

                    if selectedCategory != .home {
                        LibraryGridSection(
                            items: items,
                            groupedItems: groupedItems,
                            recentlyAdded: recentlyAdded,
                            featuredCarouselItems: featuredCarouselItems,
                            selectedCategory: selectedCategory,
                            searchText: searchText,
                            selectedNetworks: selectedNetworks,
                            namespace: namespace,
                            isFastScrolling: isFastScrolling,
                            disableHover: false,
                            columns: columns,
                            viewModel: viewModel,
                            onLoadMore: onLoadMore
                        )
                        .transition(.opacity)
                    }
                }
            }
            .scrollBounceBehavior(selectedCategory == .home ? .always : .basedOnSize)
            .scrollIndicators(.hidden)
            .background {
                ScrollVelocityTracker(isFastScrolling: $isFastScrolling, scrollTask: $scrollTask)
            }
        }
        .onChange(of: SleepManager.shared.isAsleep) { oldValue, isAsleep in
            if isAsleep {
                scrollTask?.cancel()
                isFastScrolling = false
            }
        }
        .onAppear {
            viewModel.fetchTrendingIfNeeded()
        }
    }
}
