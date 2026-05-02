import SwiftData
import SwiftUI

struct ContentView: View {
    @Namespace private var posterNamespace
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = MediaViewModel()
    @State private var themeCoordinator = AppThemeCoordinator.shared
    @State private var isSearchActive = false
    @State private var sidebarSelection: NavigationCategory? = .home
    @State private var selectedHeroItem: MediaItem? = nil
    @State private var isSyncHovered = false

    @State private var updateTask: Task<Void, Never>?

    private func updateDisplayedItems(delay: UInt64 = 150_000_000) {
        // Skip updating if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        // Zero-Jitter Sequencing: If we just switched categories, give the transition
        // a moment to breathe before building the new grid items.
        let executionDelay = delay

        updateTask?.cancel()
        updateTask = Task {
            try? await Task.sleep(nanoseconds: executionDelay)
            if Task.isCancelled { return }

            let currentSearchText = viewModel.searchText
            let category = viewModel.selectedCategory
            let sortOrder = viewModel.currentSortOrder
            let networks = viewModel.selectedNetworks
            let language = viewModel.selectedLanguage
            let groupBy = viewModel.currentGroupBy

            // Optimization: Skip heavy data load if moving to Discovery Hub
            if category == .discover { return }

            // Reset pagination for new filter/sort
            await MainActor.run {
                viewModel.displayedItems = []
                viewModel.currentOffset = 0
                viewModel.isLoadingMore = false
            }

            do {
                let filterActor = MediaFilterActor(modelContainer: modelContext.container)

                // Phase 4 Optimization: Pagination limit
                let limit = viewModel.pageSize
                let result = try await filterActor.filterAndSort(
                    category: category,
                    searchText: currentSearchText,
                    sortOrder: sortOrder,
                    network: networks,
                    language: language,
                    groupBy: groupBy,
                    limit: limit,
                    offset: 0
                )
                
                let allIDs = (try? await filterActor.allLibraryTMDBIDs()) ?? []

                if Task.isCancelled { return }

                await MainActor.run {
                    viewModel.totalItemCount = result.totalCount
                    viewModel.displayedItems = result.displayed
                    viewModel.featuredUpcomingItems = result.featuredUpcoming
                    viewModel.recentlyAddedItems = result.recentlyAdded
                    viewModel.homeContinueWatchingItems = result.homeContinueWatching
                    viewModel.groupedItems = result.grouped
                    viewModel.libraryTMDBIDs = allIDs
                    viewModel.isInitialLoading = false

                    // Update Mood Theme based on current visible content
                    let moodColors = result.displayed.prefix(10).compactMap { $0.themeColorHex.flatMap { Color(hex: $0) } }
                    themeCoordinator.updateMood(for: Array(moodColors), colorScheme: colorScheme)

                    // If we just loaded "All" category, also extract colors for Sidebar
                    if category == .discover || category == .all {
                        // Extract network colors in background
                        let container = modelContext.container
                        Task.detached(priority: .background) {
                            let sync = DiscoverySyncService(modelContainer: container)
                            await sync.syncLibrary(force: false)
                        }
                    }
                }

                // Async Recommendation Calculation (Only for Home view)
                if category == .home {
                    // Spread the load: Wait 2 seconds before heavy taste analytics
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if Task.isCancelled { return }

                    let tasteActor = TasteActor(modelContainer: modelContext.container)
                    let recs = await tasteActor.calculateRecommendations()

                    await MainActor.run {
                        // Find metadata for these IDs
                        self.viewModel.recommendations = recs.compactMap {
                            (id, reason) -> MediaThumbnailMetadata? in
                            guard let item = modelContext.model(for: id) as? MediaItem,
                                !item.isDeleted
                            else { return nil }
                            return MediaThumbnailMetadata(item: item, recommendationReason: reason)
                        }
                    }
                }
            } catch {
                print("Error filtering items: \(error)")
            }
        }
    }

    private func loadMoreItems() {
        guard !viewModel.isLoadingMore && viewModel.displayedItems.count < viewModel.totalItemCount
        else { return }

        viewModel.isLoadingMore = true
        let nextOffset = viewModel.displayedItems.count

        Task {
            let currentSearchText = viewModel.searchText
            let category = viewModel.selectedCategory
            let sortOrder = viewModel.currentSortOrder
            let networks = viewModel.selectedNetworks
            let language = viewModel.selectedLanguage
            let groupBy = viewModel.currentGroupBy
            let limit = viewModel.pageSize

            do {
                let filterActor = MediaFilterActor(modelContainer: modelContext.container)
                let result = try await filterActor.filterAndSort(
                    category: category,
                    searchText: currentSearchText,
                    sortOrder: sortOrder,
                    network: networks,
                    language: language,
                    groupBy: groupBy,
                    limit: limit,
                    offset: nextOffset
                )

                await MainActor.run {
                    viewModel.displayedItems.append(contentsOf: result.displayed)
                    viewModel.isLoadingMore = false
                    viewModel.currentOffset = nextOffset
                }
            } catch {
                print("Error loading more: \(error)")
                await MainActor.run { viewModel.isLoadingMore = false }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if isSearchActive {
            SearchView(
                searchText: $viewModel.searchText,
                isSearchActive: $isSearchActive,
                submitTrigger: viewModel.searchSubmitTrigger,
                initialType: currentMediaType,
                viewModel: viewModel
            ) { item in
                viewModel.navigationPath.append(item)
            }
        } else if viewModel.selectedCategory == .discover {
            DiscoveryHubView(namespace: posterNamespace, viewModel: viewModel) { filter in
                viewModel.navigationPath.append(filter)
            }
        } else if viewModel.selectedCategory == .upcoming {
            ReleaseCalendarView(viewModel: viewModel)
                .transition(.asymmetric(insertion: .opacity, removal: .opacity))
        } else if viewModel.selectedCategory == .insights {
            InsightsView()
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
                    if let item = modelContext.model(for: metadata.id) as? MediaItem {
                        viewModel.navigationPath.append(item)
                    }
                },
                onNetworkSelected: { networks in
                    onNetworkSelected(networks)
                },
                onLoadMore: {
                    loadMoreItems()
                },
                viewModel: viewModel
            )
        }
    }

    var body: some View {
        NavigationSplitView {
            SidebarNavigation(selection: $sidebarSelection)
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)  // Allow appBackground to show through sidebar
                .navigationTitle("Library")
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
                .onChange(of: sidebarSelection) { _, newValue in
                    if let category = newValue {
                        viewModel.selectedCategory = category
                        viewModel.selectedNetworks = nil
                        viewModel.selectedLanguage = nil
                        viewModel.isInitialLoading = true  // Reset loading state for category switch
                        updateDisplayedItems()
                    }
                }
        } detail: {
            NavigationStack(path: $viewModel.navigationPath) {
                mainContent
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isSearchActive)
                    .navigationTitle(
                        isSearchActive
                            ? "Search" : viewModel.navigationTitle(for: viewModel.selectedCategory)
                    )
                    .navigationDestination(for: MediaItem.self) { item in
                        DetailView(item: item, namespace: posterNamespace) { actorName in
                            viewModel.selectedCategory = .all  // Switch to All to check all titles
                            viewModel.searchText = actorName
                            viewModel.navigationPath = NavigationPath()  // CLEAR NAVIGATION STACK
                            isSearchActive = true  // ACTIVATE SEARCH VIEW
                            updateDisplayedItems()
                        }
                    }
                    .navigationDestination(for: PersistentIdentifier.self) { id in
                        if let item = modelContext.model(for: id) as? MediaItem {
                            DetailView(item: item, namespace: posterNamespace) { actorName in
                                viewModel.selectedCategory = .all
                                viewModel.searchText = actorName
                                viewModel.navigationPath = NavigationPath()
                                isSearchActive = true
                                updateDisplayedItems()
                            }
                        }
                    }
                    .navigationDestination(for: DiscoveryFilter.self) { filter in
                        FilteredLibraryGridView(
                            filter: filter, namespace: posterNamespace,
                            isFastScrolling: $viewModel.isFastScrolling)
                    }
                    .searchable(
                        text: $viewModel.searchText, isPresented: $isSearchActive,
                        placement: .automatic, prompt: "Search movies & shows"
                    )
                    .onSubmit(of: .search) {
                        viewModel.searchSubmitTrigger += 1
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .mediaStateChanged)) { _ in
                        updateDisplayedItems(delay: 150_000_000)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .mediaItemRefreshed)) { _ in
                        updateDisplayedItems(delay: 150_000_000)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .mediaItemsBulkRefreshed)) { _ in
                        updateDisplayedItems(delay: 150_000_000)
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            if !isSearchActive && isSortable {
                                displaySettingsMenu
                            }
                        }

                        ToolbarItem(placement: .primaryAction) {
                            if !isSearchActive && isRefreshable {
                                refreshButton
                            }
                        }
                    }
                    .background {
                        Group {
                            Button("") { sidebarSelection = .home }.keyboardShortcut(
                                "1", modifiers: .command)
                            Button("") { sidebarSelection = .upcoming }.keyboardShortcut(
                                "2", modifiers: .command)
                            Button("") { sidebarSelection = .inProgress }
                                .keyboardShortcut("3", modifiers: .command)
                            Button("") { sidebarSelection = .watchlist }
                                .keyboardShortcut("4", modifiers: .command)
                            Button("") { sidebarSelection = .all }.keyboardShortcut(
                                "5", modifiers: .command)

                            Button("") { isSearchActive = true }
                               .keyboardShortcut("f", modifiers: .command)
                            }
                            .opacity(0)
                            }
                            }
                            }
                            .appBackground(
                            network: viewModel.selectedNetworks?.first, category: viewModel.selectedCategory.rawValue
                            )  // Apply to the whole NavigationSplitView
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: viewModel.selectedCategory)
        .animation(.smooth(duration: 0.4), value: isSearchActive)
        .task {
            // Trigger initial data load
            updateDisplayedItems()
        }
    }

    private func navigate(to metadata: MediaThumbnailMetadata) {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            if let item = modelContext.model(for: metadata.id) as? MediaItem {
                viewModel.navigationPath.append(item)
            }
        }
    }

    private func onNetworkSelected(_ networks: [String]) {
        withAnimation {
            viewModel.selectedNetworks = networks.isEmpty ? nil : networks
            updateDisplayedItems()
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            if viewModel.selectedCategory == .discover {
                ImageCache.shared.clearFullCache()
                viewModel.discoveryRefreshTrigger += 1
            } else {
                performLibrarySync()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isSyncHovered ? Color.primary.opacity(0.1) : Color.clear)
                    .frame(width: 32, height: 32)

                if DataService.shared.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .bold))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isSyncHovered = hovering
            }
        }
        .help("Sync Library")
        .disabled(DataService.shared.isRefreshing)
    }

    @ViewBuilder
    private var displaySettingsMenu: some View {
        let cat = viewModel.selectedCategory

        Menu {
            Picker(
                "Sort By",
                selection: Binding(
                    get: { viewModel.currentSortOrder },
                    set: {
                        viewModel.categorySortOrders[cat] = $0
                        updateDisplayedItems()
                    }
                )
            ) {
                ForEach(SortOrder.allCases) { order in
                    Label(order.rawValue, systemImage: order.icon)
                        .tag(order)
                }
            }

            Picker(
                "Group By",
                selection: Binding(
                    get: { viewModel.currentGroupBy },
                    set: {
                        viewModel.categoryGroupBys[cat] = $0
                        updateDisplayedItems()
                    }
                )
            ) {
                ForEach(GroupBy.allCases) { group in
                    Label(group.rawValue, systemImage: group.icon)
                        .tag(group)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    private var currentMediaType: MediaType? {
        return MediaType(rawValue: viewModel.selectedCategory.rawValue)
    }

    private var isSortable: Bool {
        let cat = viewModel.selectedCategory
        if cat == .discover || cat == .insights || cat == .home || cat == .upcoming { return false }
        return true
    }

    private var isRefreshable: Bool {
        let cat = viewModel.selectedCategory
        if cat == .insights || cat == .home { return false }
        return true
    }

    private func performLibrarySync() {
        guard !DataService.shared.isRefreshing else { return }

        let descriptor = FetchDescriptor<MediaItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }

        DataService.shared.refreshMetadata(for: items, modelContext: modelContext, force: true)
    }
}
