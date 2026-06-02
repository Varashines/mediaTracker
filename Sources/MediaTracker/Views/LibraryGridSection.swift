import SwiftUI
import SwiftData

struct LibraryGridSection: View {
    let items: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recentlyAdded: [MediaThumbnailMetadata]
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let selectedCategory: NavigationCategory
    let searchText: String
    let selectedNetworks: [String]?
    let namespace: Namespace.ID
    let isFastScrolling: Bool
    let disableHover: Bool
    let columns: [GridItem]
    let viewModel: MediaViewModel
    let onLoadMore: () -> Void
    
    var isCategoryPage: Bool {
        return selectedCategory == .movie || selectedCategory == .tvShow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if items.isEmpty && groupedItems.isEmpty {
                LibraryEmptyStateView(category: selectedCategory) {
                    withAnimation {
                        viewModel.filter.selectedCategory = .discover
                    }
                }
            } else {
                if selectedCategory == .all && searchText.isEmpty
                    && selectedNetworks == nil
                {
                    RecentlyAddedRow(
                        items: recentlyAdded, isFastScrolling: isFastScrolling)
                }

                if viewModel.filter.currentGroupBy == .none {
                    MainMediaGrid(
                        items: items,
                        featuredCount: 0,
                        isCategoryPage: isCategoryPage, namespace: namespace,
                        isFastScrolling: isFastScrolling,
                        disableHover: disableHover,
                        selectedCollectionID: viewModel.collection.selectedCollectionID,
                        onLoadMore: onLoadMore,
                        columns: columns,
                        isLoadingMore: viewModel.pagination.isLoadingMore
                    )
                } else {
                    GroupedMediaGrid(
                        groupedItems: groupedItems,
                        selectedCategoryRef: selectedCategory,
                        viewModel: viewModel, namespace: namespace,
                        isFastScrolling: isFastScrolling,
                        disableHover: disableHover,
                        columns: columns)
                }
            }
        }
    }
}
