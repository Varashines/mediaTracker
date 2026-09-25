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
                            }
                        }
                        .padding(AppTheme.Spacing.pageMargin)
                        .shimmering()
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
                    && (selectedNetworks?.isEmpty ?? true)
                {
                    RecentlyAddedRow(
                        items: recentlyAdded, namespace: namespace)
                }

                if viewModel.filter.currentGroupBy == .none {
                    MainMediaGrid(
                        items: items,
                        isCategoryPage: isCategoryPage, namespace: namespace,
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
                        disableHover: disableHover,
                        columns: columns)
                }
            }
        }
        // Animate only on category/search changes — constructing a full
        // FilterSnapshot (12 property reads) as the animation value on every
        // body eval was pure overhead with no visual benefit.
        .animation(AppTheme.Animation.easeInOut, value: selectedCategory)
        .animation(AppTheme.Animation.easeInOut, value: searchText)
    }
}
