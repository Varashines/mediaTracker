import SwiftUI
import SwiftData

struct CategoryRouterView: View {
    @Binding var sidebarSelection: SidebarItem?
    @Binding var isSearchActive: Bool
    var posterNamespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    var modelContainer: ModelContainer
    var onLoadMore: (() -> Void)?

    var body: some View {
        if isSearchActive {
            SearchView(
                searchText: $viewModel.searchText,
                isSearchActive: $isSearchActive,
                submitTrigger: viewModel.searchSubmitTrigger,
                initialType: currentMediaType,
                viewModel: viewModel,
                onSelectLocal: { item in
                    viewModel.navigationPath.append(item.persistentModelID)
                },
                modelContainer: modelContainer
            )
        } else if viewModel.selectedCategory == .discover {
            DiscoveryHubView(namespace: posterNamespace, viewModel: viewModel) { filter in
                viewModel.navigationPath.append(filter)
            }
        } else if viewModel.selectedCategory == .upcoming {
            ReleaseCalendarView(viewModel: viewModel)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
        } else if viewModel.selectedCategory == .insights {
            InsightsView()
        } else if viewModel.selectedCategory == .smartHub && viewModel.selectedCollectionID == nil {
            SmartCollectionsHubView(namespace: posterNamespace, selection: $sidebarSelection)
        } else {
            MainLibraryView(
                items: viewModel.displayedItems,
                featuredCarouselItems: viewModel.featuredUpcomingItems,
                recentlyAdded: viewModel.recentlyAddedItems,
                homeContinueWatching: viewModel.homeContinueWatchingItems,
                groupedItems: viewModel.groupedItems,
                recommendations: viewModel.recommendations,
                selectedCategory: viewModel.selectedCategory,
                showingUpcomingOnly: viewModel.selectedCategory == .upcoming,
                searchText: viewModel.searchText,
                selectedNetworks: viewModel.selectedNetworks,
                namespace: posterNamespace,
                isFastScrolling: $viewModel.isFastScrolling,
                onSelectHero: { metadata in
                    if let item = modelContainer.mainContext.model(for: metadata.id) as? MediaItem {
                        viewModel.navigationPath.append(item)
                    }
                },
                onNetworkSelected: { networks in
                    withAnimation {
                        viewModel.selectedNetworks = networks.isEmpty ? nil : networks
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
        MediaType(rawValue: viewModel.selectedCategory.rawValue)
    }
}
