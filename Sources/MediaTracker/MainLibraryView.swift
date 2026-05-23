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
            let columns: [GridItem] = [
                GridItem(.adaptive(minimum: 170, maximum: 200), spacing: AppTheme.Spacing.large)
            ]

            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.section, pinnedViews: [.sectionHeaders]) {
                    if selectedCategory == .home && searchText.isEmpty && selectedNetworks == nil {
                        HomeViewSections(
                            homeContinueWatching: homeContinueWatching,
                            featuredCarouselItems: featuredCarouselItems,
                            groupedItems: groupedItems,
                            recommendations: recommendations,
                            namespace: namespace,
                            isFastScrolling: isFastScrolling,
                            onSelectHero: onSelectHero,
                            onCategorySelected: onCategorySelected
                        )
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
                            LibraryGridSection(
                                items: items,
                                groupedItems: groupedItems,
                                recentlyAdded: recentlyAdded,
                                featuredCarouselItems: featuredCarouselItems,
                                selectedCategory: selectedCategory,
                                showingUpcomingOnly: showingUpcomingOnly,
                                searchText: searchText,
                                selectedNetworks: selectedNetworks,
                                namespace: namespace,
                                isFastScrolling: isFastScrolling,
                                columns: columns,
                                viewModel: viewModel,
                                onLoadMore: onLoadMore
                            )
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
                                        .padding(.top, AppTheme.Spacing.micro)
                                        .padding(.bottom, AppTheme.Spacing.small)
                                }
                            }
                        }
                    }
                }
                .padding(.top, AppTheme.Spacing.section)
                .padding(.bottom, AppTheme.Spacing.large)
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
