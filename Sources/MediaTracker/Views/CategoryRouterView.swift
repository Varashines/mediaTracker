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
                .transition(.move(edge: .top).combined(with: .opacity))
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
                    withAnimation(AppTheme.Animation.springSnappy) {
                        viewModel.filter.selectedNetworks = networks.isEmpty ? nil : networks
                        viewModel.filterSubject.send()
                    }
                },
                onCategorySelected: { category in
                    withAnimation(AppTheme.Animation.springSnappy) {
                        viewModel.collection.selectedCollectionID = nil
                        viewModel.collection.selectedCollectionName = nil
                        sidebarSelection = .category(category)
                    }
                },
                onBack: {
                    withAnimation(AppTheme.Animation.springSnappy) {
                        sidebarSelection = .category(.smartHub)
                    }
                },
                onLoadMore: { onLoadMore?() },
                onTrendingAdd: { result in
                    let typePrefix = result.type == .movie ? "movie" : "tv"
                    let uniqueID = "\(typePrefix)_\(result.id)"
                    let container = modelContainer
                    let viewModelCopy = viewModel

                    Task {
                        let service = BackgroundDataService(modelContainer: container)
                        let (id, isExisting) = await service.createNewMediaItem(
                            uniqueID: uniqueID,
                            tmdbID: Int(result.id) ?? 0,
                            type: result.type,
                            title: result.title,
                            overview: result.overview,
                            posterURL: result.posterURL,
                            releaseDateString: result.releaseDate
                        )
                        if isExisting {
                            AppErrorState.shared.showToast("Already in Library", style: .info)
                        } else {
                            AppErrorState.shared.showToast("Added to Library", style: .success)
                            FeedbackManager.shared.trigger(.addToLibrary)
                        }
                        if let id = id {
                            await MainActor.run {
                                viewModelCopy.navigationPath.append(id)
                            }
                        }
                    }
                },
                viewModel: viewModel
            )
        }
    }

    private var currentMediaType: MediaType? {
        MediaType(rawValue: viewModel.filter.selectedCategory.rawValue)
    }
}
