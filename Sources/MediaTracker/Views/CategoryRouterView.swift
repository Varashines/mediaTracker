import SwiftUI
import SwiftData

struct CategoryRouterView: View {
    @Binding var sidebarSelection: SidebarItem?
    @Binding var isSearchActive: Bool
    var posterNamespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    var modelContainer: ModelContainer
    var onLoadMore: (() -> Void)?
    var refreshID: Int = 0

    var body: some View {
        ZStack {
            normalContent
                .opacity(isSearchActive ? 0 : 1)

            if isSearchActive {
                SearchView(
                    searchText: $viewModel.filter.searchText,
                    isSearchActive: $isSearchActive,
                    initialType: currentMediaType,
                    viewModel: viewModel,
                    onSelectLocal: { item in
                        viewModel.navigationPath.append(item.persistentModelID)
                    },
                    modelContainer: modelContainer
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
    }

    @ViewBuilder
    private var normalContent: some View {
        if viewModel.filter.selectedCategory == .discover {
            DiscoveryHubView(namespace: posterNamespace, viewModel: viewModel) { filter in
                viewModel.navigationPath.append(filter)
            }
        } else if viewModel.filter.selectedCategory == .upcoming {
            ReleaseCalendarView(viewModel: viewModel, refreshID: refreshID)
        } else if viewModel.filter.selectedCategory == .insights {
            InsightsView(refreshID: refreshID)
        } else if viewModel.filter.selectedCategory == .smartHub && viewModel.collection.selectedCollectionID == nil {
            SmartCollectionsHubView(namespace: posterNamespace, selection: $sidebarSelection, refreshID: refreshID)
        } else {
            MainLibraryView(
                items: viewModel.display.displayedItems,
                featuredCarouselItems: viewModel.display.featuredUpcomingItems,
                recentlyAdded: viewModel.display.recentlyAddedItems,
                homeContinueWatching: viewModel.display.homeContinueWatchingItems,
                groupedItems: viewModel.display.groupedItems,
                recommendations: viewModel.display.recommendations,
                pickOfTheDay: viewModel.display.pickOfTheDay,
                selectedCategory: viewModel.filter.selectedCategory,
                searchText: viewModel.filter.searchText,
                selectedNetworks: viewModel.filter.selectedNetworks,
                namespace: posterNamespace,
                isFastScrolling: $viewModel.pagination.isFastScrolling,
                onSelectHero: { metadata in
                    if let item = modelContainer.mainContext.model(for: metadata.id) as? MediaItem {
                        viewModel.navigationPath.append(item)
                    }
                },
                onNetworkSelected: { networks in
                    withAnimation {
                        viewModel.filter.selectedNetworks = networks.isEmpty ? nil : networks
                        viewModel.filterSubject.send()
                    }
                },
                onCategorySelected: { category in
                    withAnimation {
                        sidebarSelection = .category(category)
                    }
                },
                onBack: {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        sidebarSelection = .category(.smartHub)
                    }
                },
                onLoadMore: { onLoadMore?() },
                viewModel: viewModel
            )
        }
    }

    private var currentMediaType: MediaType? {
        MediaType(rawValue: viewModel.filter.selectedCategory.rawValue)
    }
}
