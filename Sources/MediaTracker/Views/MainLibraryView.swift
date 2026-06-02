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

    var showsFilterBar: Bool {
        switch selectedCategory {
        case .all, .movie, .tvShow, .completed: return true
        default: return false
        }
    }

    var body: some View {
        GeometryReader { (mainGeo: GeometryProxy) in
            let usePortraitCards = viewModel.collection.selectedCollectionID != nil || selectedCategory.isSmartCategory
            let columns: [GridItem] = usePortraitCards
                ? [GridItem(.adaptive(minimum: 160, maximum: 175), spacing: 10)]
                : [GridItem(.adaptive(minimum: 160, maximum: 175), spacing: 16)]

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

                    if selectedCategory != .home {
                        if viewModel.collection.selectedCollectionID != nil || selectedCategory.isSmartCategory {
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
                        } else {
                            Section {
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
                                    disableHover: selectedCategory == .all || selectedCategory == .movie || selectedCategory == .tvShow,
                                    columns: columns,
                                    viewModel: viewModel,
                                    onLoadMore: onLoadMore
                                )
                            } header: {
                                VStack(alignment: .leading, spacing: 0) {
                                    LibraryHeaderView(
                                        selectedCategory: selectedCategory,
                                        selectedNetworks: selectedNetworks, isCategoryPage: isCategoryPage,
                                        onNetworkSelected: onNetworkSelected, onBack: onBack,
                                        viewModel: viewModel)

                                    if showsFilterBar {
                                        LibraryFilterBar(viewModel: viewModel)
                                            .padding(.top, AppTheme.Spacing.micro)
                                            .padding(.bottom, AppTheme.Spacing.tiny)
                                    }
                                }
                            }
                        }
                    }
                }
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
