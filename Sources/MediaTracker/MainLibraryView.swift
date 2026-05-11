import SwiftData
import SwiftUI

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
    let onCategorySelected: (NavigationCategory) -> Void
    let onBack: (() -> Void)?
    let onLoadMore: () -> Void
    var viewModel: MediaViewModel

    @Environment(\.modelContext) private var modelContext
    @State private var visibleCount = 40
    @State private var scrollTask: Task<Void, Never>?

    var isCategoryPage: Bool {
        return selectedCategory == .movie || selectedCategory == .tvShow
    }

    var isMainSection: Bool {
        return true
    }

    var body: some View {
        GeometryReader { (mainGeo: GeometryProxy) in
            let spacing: CGFloat = 20
            let columns: [GridItem] = [
                GridItem(.adaptive(minimum: 170, maximum: 200), spacing: spacing)
            ]

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30, pinnedViews: [.sectionHeaders]) {
                    if selectedCategory == .home && searchText.isEmpty && selectedNetworks == nil {
                        // 1. CONTINUE WATCHING
                        ContinueWatchingCarousel(
                            items: homeContinueWatching, namespace: namespace,
                            isFastScrolling: isFastScrolling, onSelect: onSelectHero
                        ) {
                            onCategorySelected(.discover)
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 20)

                        // 2. COMING SOON (Limited to 10)
                        let comingSoon = featuredCarouselItems.isEmpty ? (groupedItems.first(where: { $0.0 == "Coming Soon" })?.1 ?? []) : featuredCarouselItems
                        if !comingSoon.isEmpty {
                            FeaturedUpcomingCarousel(
                                items: Array(comingSoon.prefix(10)), namespace: namespace,
                                isFastScrolling: isFastScrolling, onSelect: onSelectHero
                            )
                            .padding(.bottom, 20)
                        }

                        // 3. FOR YOU (Recommendations)
                        ForYouCarousel(
                            items: recommendations, namespace: namespace,
                            isFastScrolling: isFastScrolling, onSelect: onSelectHero
                        )
                        .padding(.bottom, 20)
                    }

                    if showingUpcomingOnly && searchText.isEmpty && selectedNetworks == nil
                        && !featuredCarouselItems.isEmpty
                    {
                        FeaturedUpcomingCarousel(
                            items: featuredCarouselItems, namespace: namespace,
                            isFastScrolling: isFastScrolling, onSelect: onSelectHero)
                    }

                    if selectedCategory != .home {
                        Section {
                            VStack(alignment: .leading, spacing: 15) {
                                if items.isEmpty && groupedItems.isEmpty {
                                    if viewModel.isInitialLoading {
                                        LoadingGridSkeleton(
                                            selectedCategory: selectedCategory, columns: columns)
                                    } else {
                                        LibraryEmptyStateView(category: selectedCategory) {
                                            withAnimation {
                                                viewModel.selectedCategory = .discover
                                            }
                                        }
                                    }
                                } else {
                                    if selectedCategory == .all && searchText.isEmpty
                                        && selectedNetworks == nil
                                    {
                                        RecentlyAddedRow(
                                            items: recentlyAdded, isFastScrolling: isFastScrolling)
                                    }

                                    if viewModel.currentGroupBy == .none {
                                        MainMediaGrid(
                                            items: items,
                                            featuredCount: showingUpcomingOnly
                                                ? featuredCarouselItems.count : 0,
                                            showingUpcomingOnly: showingUpcomingOnly,
                                            isCategoryPage: isCategoryPage, namespace: namespace,
                                            isFastScrolling: isFastScrolling,
                                            selectedCollectionID: viewModel.selectedCollectionID,
                                            onLoadMore: onLoadMore, columns: columns)
                                    } else {
                                        GroupedMediaGrid(
                                            groupedItems: groupedItems,
                                            selectedCategoryRef: selectedCategory,
                                            showingUpcomingOnly: showingUpcomingOnly,
                                            viewModel: viewModel, namespace: namespace,
                                            isFastScrolling: isFastScrolling, columns: columns)
                                    }
                                }
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 0) {
                                LibraryHeaderView(
                                    selectedCategory: selectedCategory,
                                    selectedNetworks: selectedNetworks, isCategoryPage: isCategoryPage,
                                    isMainSection: isMainSection,
                                    onNetworkSelected: onNetworkSelected, onBack: onBack,
                                    viewModel: viewModel)

                                if isMainSection {
                                    LibraryFilterBar(viewModel: viewModel)
                                        .padding(.top, 5)
                                        .padding(.bottom, 12)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 30)
                .padding(.bottom, 20)
                .background {
                    ScrollVelocityTracker(
                        isFastScrolling: $isFastScrolling, scrollTask: $scrollTask)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollClipDisabled()
            .onChange(of: SleepManager.shared.isAsleep) { oldValue, isAsleep in
                if isAsleep {
                    scrollTask?.cancel()
                    isFastScrolling = false
                }
            }
            .onAppear { visibleCount = 40 }
            .onChange(of: items.count) { visibleCount = 40 }
        }
    }
}
