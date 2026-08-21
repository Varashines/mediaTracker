import SwiftUI
import SwiftData

struct LibraryGridSection: View {
    let items: [MediaThumbnailMetadata]
    var isLoading: Bool = false
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
                if isLoading {
                    // First fetch in flight — skeleton instead of flashing the
                    // empty state on populated libraries during category switches.
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(0..<12, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                                    .frame(width: 160, height: 240)
                                    .shimmering()
                            }
                        }
                        .padding(AppTheme.Spacing.pageMargin)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                } else {
                    LibraryEmptyStateView(category: selectedCategory) {
                        withAnimation(AppTheme.Animation.springSnappy) {
                            viewModel.filter.selectedCategory = .discover
                        }
                    }
                }
            } else {
                if selectedCategory == .all && searchText.isEmpty
                    && selectedNetworks == nil
                {
                    RecentlyAddedRow(
                        items: recentlyAdded, isFastScrolling: isFastScrolling, namespace: namespace)
                }

                if viewModel.filter.currentGroupBy == .none {
                    MainMediaGrid(
                        items: items,
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
        .animation(AppTheme.Animation.easeInOut, value: FilterSnapshot(from: viewModel))
    }
}
