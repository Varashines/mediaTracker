import SwiftData
import SwiftUI
import Combine

struct ContentView: View {
    @Namespace private var posterNamespace
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var collections: [MediaCollection]
    @State private var viewModel = MediaViewModel()
    @State private var themeCoordinator = AppThemeCoordinator.shared
    @State private var isSearchActive = false
    @State private var sidebarSelection: SidebarItem? = .category(.home)
    @State private var selectedHeroItem: MediaItem? = nil
    @State private var isSyncHovered = false
    @State private var showingBulkManager = false


    @State private var updateTask: Task<Void, Never>?

    private func performUpdate() {
        // Skip updating if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        // Automatically heal stale "Coming Soon" items before sorting
        checkAndRepairStaleMetadata()

        let currentSearchText = viewModel.searchText
        let category = viewModel.selectedCategory
        let sortOrder = viewModel.currentSortOrder
        let networks = viewModel.selectedNetworks
        let language = viewModel.selectedLanguage
        let groupBy = viewModel.currentGroupBy
        let collectionID = viewModel.selectedCollectionID

        updateTask?.cancel()
        updateTask = Task {
            // Optimization: Skip heavy data load if moving to Discovery Hub or Settings
            if category == .discover || category == .settings || (category == .collectionsHub && collectionID == nil) { return }

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
                    collectionID: collectionID,
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
                    viewModel.spotlightHero = result.spotlightHero
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
                    collectionID: viewModel.selectedCollectionID,
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
                viewModel: viewModel,
                onSelectLocal: { item in
                    viewModel.navigationPath.append(item.persistentModelID)
                },
                modelContainer: modelContext.container
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
        } else if viewModel.selectedCategory == .settings {
            SettingsView()
        } else if viewModel.selectedCategory == .collectionsHub && viewModel.selectedCollectionID == nil {
            CollectionsManagementView(viewModel: viewModel, sidebarSelection: $sidebarSelection)
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
                onCategorySelected: { category in
                    withAnimation {
                        sidebarSelection = .category(category)
                    }
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
                .scrollContentBackground(.hidden)
                .navigationTitle("Library")
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
                .onChange(of: sidebarSelection) { _, newValue in
                    if let selection = newValue {
                        switch selection {
                        case .category(let category):
                            viewModel.selectedCategory = category
                            viewModel.selectedNetworks = nil
                            viewModel.selectedLanguage = nil
                            viewModel.isInitialLoading = true
                            
                            if category != .collectionsHub {
                                viewModel.selectedCollectionID = nil
                            }
                        case .collection(let id, let name, _):
                            viewModel.selectedCategory = .collectionsHub
                            viewModel.selectedCollectionID = id
                            viewModel.selectedCollectionName = name
                            viewModel.isInitialLoading = true
                        }
                        
                        viewModel.filterSubject.send()
                    }
                }
        } detail: {
            NavigationStack(path: $viewModel.navigationPath) {
                ZStack {
                    mainContent
                    
                    if viewModel.showingNoteOverlay, let collectionID = viewModel.selectedCollectionID {
                        NoteOverlayView(viewModel: viewModel, collectionID: collectionID)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(100)
                    }
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isSearchActive)
                .navigationTitle(
                    isSearchActive
                        ? "Search" : viewModel.navigationTitle(for: viewModel.selectedCategory)
                )
                .navigationDestination(for: MediaItem.self) { item in
                    DetailView(item: item, namespace: posterNamespace) { actorName in
                        viewModel.selectedCategory = .all
                        viewModel.searchText = actorName
                        viewModel.navigationPath = NavigationPath()
                        isSearchActive = true
                        viewModel.filterSubject.send()
                    }
                }
                .navigationDestination(for: PersistentIdentifier.self) { id in
                    if let item = modelContext.model(for: id) as? MediaItem {
                        DetailView(item: item, namespace: posterNamespace) { actorName in
                            viewModel.selectedCategory = .all
                            viewModel.searchText = actorName
                            viewModel.navigationPath = NavigationPath()
                            isSearchActive = true
                            viewModel.filterSubject.send()
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
                    LibraryStatsActor.clearCache()
                    viewModel.filterSubject.send()
                }
                .onReceive(NotificationCenter.default.publisher(for: .mediaItemRefreshed)) { _ in
                    LibraryStatsActor.clearCache()
                    viewModel.filterSubject.send()
                }
                .onReceive(NotificationCenter.default.publisher(for: .mediaItemsBulkRefreshed)) { _ in
                    LibraryStatsActor.clearCache()
                    viewModel.filterSubject.send()
                }
                .task(id: viewModel.searchText) {
                    viewModel.filterSubject.send()
                }
                .onReceive(viewModel.filterSubject.debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
                    performUpdate()
                }
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if viewModel.selectedCollectionID != nil && !isSearchActive {
                            HStack(spacing: 4) {
                                Button {
                                    withAnimation {
                                        viewModel.selectedCollectionID = nil
                                    }
                                    viewModel.filterSubject.send()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .help("Back to Collections")
                                
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        viewModel.showingNoteOverlay.toggle()
                                    }
                                } label: {
                                    let icon = viewModel.showingNoteOverlay ? "bubble.left.and.bubble.right.fill" : "bubble.left.fill"
                                    let hasNote = !viewModel.currentCollectionNote.isEmpty
                                    Image(systemName: icon)
                                        .font(.system(size: 14))
                                        .foregroundStyle(hasNote ? Color.blue : Color.secondary)
                                }
                                .help("Collection Notes")

                                Button {
                                    showingBulkManager = true
                                } label: {
                                    Image(systemName: "plus.square.on.square")
                                        .font(.system(size: 14))
                                }
                                .help("Manage Items")
                            }
                        }
                    }

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
                        Button("") { sidebarSelection = .category(.home) }.keyboardShortcut("1", modifiers: .command)
                        Button("") { sidebarSelection = .category(.discover) }.keyboardShortcut("2", modifiers: .command)
                        Button("") { sidebarSelection = .category(.upcoming) }.keyboardShortcut("3", modifiers: .command)
                        Button("") { sidebarSelection = .category(.all) }.keyboardShortcut("4", modifiers: .command)
                        Button("") { sidebarSelection = .category(.movie) }.keyboardShortcut("5", modifiers: .command)
                        Button("") { sidebarSelection = .category(.tvShow) }.keyboardShortcut("6", modifiers: .command)
                        Button("") { sidebarSelection = .category(.settings) }.keyboardShortcut(",", modifiers: .command)
                        Button("") { isSearchActive = true }.keyboardShortcut("f", modifiers: .command)
                    }
                    .opacity(0)
                }
            }
        }
        .appBackground(network: viewModel.selectedNetworks?.first, category: viewModel.selectedCategory.rawValue)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: viewModel.selectedCategory)
        .animation(.smooth(duration: 0.4), value: isSearchActive)
        .sheet(isPresented: $showingBulkManager) {
            if let collectionID = viewModel.selectedCollectionID,
               let collection = collections.first(where: { $0.id == collectionID }) {
                BulkCollectionManagerView(collection: collection)
            }
        }
        .task {
            performUpdate()
            checkAndRepairMissingMetadata()
            checkAndRepairStaleMetadata()
        }
    }

    private func checkAndRepairStaleMetadata() {
        let container = modelContext.container
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            let now = Date()
            // Look for items currently marked as upcoming or with a badge that might be stale
            let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.storedIsUpcoming == true && $0.cachedNextAiringDate != nil && $0.cachedNextAiringDate! < now })
            
            if let staleItems = try? context.fetch(descriptor), !staleItems.isEmpty {
                print("♻️ Auto-healing \(staleItems.count) stale items...")
                for item in staleItems {
                    item.syncCachedProperties()
                }
                try? context.save()
                
                await MainActor.run {
                    NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
                }
            }
        }
    }

    private func checkAndRepairMissingMetadata() {
        let container = modelContext.container
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            // Fetch all and filter in memory to avoid complex Predicate compiler timeouts
            let descriptor = FetchDescriptor<MediaItem>()
            if let allItems = try? context.fetch(descriptor) {
                let missingItems = allItems.filter { $0.overview == "" || $0.posterURL == nil || $0.lastUpdated == nil || $0.cachedWatchedEpisodeCount == nil }
                if !missingItems.isEmpty {
                    await MainActor.run {
                        DataService.shared.refreshMetadata(for: missingItems, modelContext: modelContext, force: true)
                    }
                }
            }
        }
    }

    private func navigate(to metadata: MediaThumbnailMetadata) {
        if metadata.title == "Start Your Journey" {
            withAnimation {
                sidebarSelection = .category(.discover)
            }
            return
        }

        withAnimation(.smooth) {
            if let item = modelContext.model(for: metadata.id) as? MediaItem {
                viewModel.navigationPath.append(item)
            }
        }
    }

    private func onNetworkSelected(_ networks: [String]) {
        withAnimation {
            viewModel.selectedNetworks = networks.isEmpty ? nil : networks
            viewModel.filterSubject.send()
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
            Picker("Sort By", selection: Binding(
                    get: { viewModel.currentSortOrder },
                    set: {
                        viewModel.categorySortOrders[cat] = $0
                        viewModel.filterSubject.send()
                    }
                )
            ) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Label(order.rawValue, systemImage: order.icon)
                        .tag(order)
                }
            }

            Picker("Group By", selection: Binding(
                    get: { viewModel.currentGroupBy },
                    set: {
                        viewModel.categoryGroupBys[cat] = $0
                        viewModel.filterSubject.send()
                    }
                )
            ) {
                ForEach(GroupBy.allCases, id: \.self) { group in
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
        if cat == .discover || cat == .insights || cat == .home || cat == .upcoming || cat == .settings { return false }
        return true
    }

    private var isRefreshable: Bool {
        let cat = viewModel.selectedCategory
        if cat == .insights || cat == .home || cat == .settings { return false }
        return true
    }

    private func performLibrarySync() {
        guard !DataService.shared.isRefreshing else { return }

        let descriptor = FetchDescriptor<MediaItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }

        DataService.shared.refreshMetadata(for: items, modelContext: modelContext, force: true)
    }
}
