import SwiftUI
import SwiftData

struct LibraryGridSection: View {
    let items: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recentlyAdded: [MediaThumbnailMetadata]
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let selectedCategory: NavigationCategory
    let showingUpcomingOnly: Bool
    let searchText: String
    let selectedNetworks: [String]?
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let columns: [GridItem]
    let viewModel: MediaViewModel
    let onLoadMore: () -> Void
    
    var isCategoryPage: Bool {
        return selectedCategory == .movie || selectedCategory == .tvShow
    }

    var body: some View {
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
    }
}
