import SwiftUI
import SwiftData

struct MainLibraryView: View {
    let items: [MediaThumbnailMetadata]
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let homeContinueWatching: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recommendations: [MediaThumbnailMetadata]
    let selectedCategory: NavigationCategory
    let showingUpcomingOnly: Bool
    let searchText: String
    let selectedNetworks: [String]?
    let namespace: Namespace.ID
    @Binding var isFastScrolling: Bool
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onNetworkSelected: ([String]) -> Void
    let onLoadMore: () -> Void
    var viewModel: MediaViewModel

    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @State private var visibleCount = 40
    @State private var scrollTimer: Timer?
    
    var isCategoryPage: Bool {
        return selectedCategory == .movie || selectedCategory == .tvShow
    }

    var isMainSection: Bool {
        return true
    }

    var body: some View {
        GeometryReader { mainGeo in
            let spacing: CGFloat = 24
            let columns = [
                GridItem(.adaptive(minimum: 160, maximum: 200), spacing: spacing)
            ]

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if selectedCategory == .home && searchText.isEmpty && selectedNetworks == nil {
                        ContinueWatchingCarousel(items: homeContinueWatching, namespace: namespace, isFastScrolling: isFastScrolling, onSelect: onSelectHero)
                            .padding(.bottom, 20)

                        ForYouCarousel(items: recommendations, namespace: namespace, isFastScrolling: isFastScrolling, onSelect: onSelectHero)
                            .padding(.bottom, 20)
                    }

                    if showingUpcomingOnly && searchText.isEmpty && selectedNetworks == nil && !featuredCarouselItems.isEmpty {
                        FeaturedUpcomingCarousel(items: featuredCarouselItems, namespace: namespace, isFastScrolling: isFastScrolling, onSelect: onSelectHero)
                    }
                    
                    VStack(alignment: .leading, spacing: 15) {
                        LibraryHeaderView(selectedCategory: selectedCategory, selectedNetworks: selectedNetworks, isCategoryPage: isCategoryPage, isMainSection: isMainSection, appAccent: appAccent, onNetworkSelected: onNetworkSelected)
                        
                        if items.isEmpty && groupedItems.isEmpty {
                            if viewModel.isInitialLoading {
                                LoadingGridSkeleton(selectedCategory: selectedCategory, columns: columns)
                            } else {
                                LibraryEmptyStateView(category: selectedCategory) {
                                    withAnimation {
                                        viewModel.selectedCategory = .discover
                                    }
                                }
                            }
                        } else {
                            if selectedCategory == .all && searchText.isEmpty && selectedNetworks == nil {
                                RecentlyAddedRow(items: recentlyAdded, isFastScrolling: isFastScrolling)
                            }

                            if viewModel.currentGroupBy == .none && selectedCategory != .home {
                                MainMediaGrid(items: items, featuredCount: showingUpcomingOnly ? featuredCarouselItems.count : 0, showingUpcomingOnly: showingUpcomingOnly, isCategoryPage: isCategoryPage, namespace: namespace, isFastScrolling: isFastScrolling, onLoadMore: onLoadMore, columns: columns)
                            } else {
                                GroupedMediaGrid(groupedItems: groupedItems, selectedCategoryRef: selectedCategory, showingUpcomingOnly: showingUpcomingOnly, viewModel: viewModel, namespace: namespace, isFastScrolling: isFastScrolling, columns: columns)
                            }
                        }
                    }
                }
                .padding(.vertical, 20)
                .background { ScrollVelocityTracker(isFastScrolling: $isFastScrolling, scrollTimer: $scrollTimer) }
            }
            .scrollClipDisabled()
            .onChange(of: SleepManager.shared.isAsleep) { oldValue, isAsleep in
                if isAsleep {
                    scrollTimer?.invalidate()
                    isFastScrolling = false
                }
            }
            .onAppear { visibleCount = 40 }
            .onChange(of: items.count) { visibleCount = 40 }
        }
    }
}
