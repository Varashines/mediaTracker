import SwiftData
import SwiftUI
import Combine

struct ContentView: View {
    @Namespace private var posterNamespace
    @State private var viewModel = MediaViewModel()
    @State private var sidebarSelection: SidebarItem? = .category(.home)
    @State private var isSearchActive = false

    var body: some View {
        NavigationSplitView {
            SidebarNavigation(selection: $sidebarSelection)
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .navigationTitle("Library")
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
                .onChange(of: sidebarSelection) { _, newValue in
                    guard let selection = newValue else { return }
                    Task { @MainActor in
                        viewModel.navigationPath = NavigationPath()

                        switch selection {
                        case .category(let category):
                            viewModel.selectedCategory = category
                            viewModel.selectedNetworks = nil
                            viewModel.selectedLanguage = nil
                            viewModel.selectedGenre = nil
                            viewModel.selectedYear = nil
                            viewModel.selectedState = nil

                            viewModel.selectedCollectionID = nil
                        case .collection(let id, let name, _):
                            viewModel.selectedCategory = .smartHub
                            viewModel.selectedCollectionID = id
                            viewModel.selectedCollectionName = name
                            viewModel.selectedGenre = nil
                            viewModel.selectedYear = nil
                            viewModel.selectedState = nil
                        }

                        viewModel.filterSubject.send()
                    }
                }
        } detail: {
            LibraryDetailView(
                sidebarSelection: $sidebarSelection,
                isSearchActive: $isSearchActive,
                posterNamespace: posterNamespace,
                viewModel: viewModel
            )
        }
        .frame(minWidth: 900, minHeight: 600)
        .animation(.easeInOut(duration: 0.3), value: isSearchActive)
    }
}

struct LibraryDetailView: View {
    @Binding var sidebarSelection: SidebarItem?
    @Binding var isSearchActive: Bool
    var posterNamespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \MediaCollection.name) private var collections: [MediaCollection]
    
    @State private var isSyncHovered = false
    @State private var showingBulkManager = false
    private let themeCoordinator = AppThemeCoordinator.shared
    @State private var updateTask: Task<Void, Never>?

    private func getFilterActor() -> MediaFilterActor {
        MediaFilterActor.shared(modelContainer: modelContext.container)
    }

    private var categoryMoodColor: Color {
        if isSearchActive {
            return Color.blue
        }
        switch viewModel.selectedCategory {
        case .home: return Color.blue
        case .discover: return Color.purple
        case .upcoming: return Color.orange
        case .all: return Color.blue
        case .movie: return Color.indigo
        case .tvShow: return Color.teal
        case .smartHub: return Color.purple
        case .insights: return Color.green
        case .releaseRadar: return Color.pink
        default: return Color.blue
        }
    }
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            ZStack {
                let mood = themeCoordinator.categoryMoodColor == .clear ? categoryMoodColor : themeCoordinator.categoryMoodColor
                LibraryBackgroundView(mood: mood)

                CategoryRouterView(
                    sidebarSelection: $sidebarSelection,
                    isSearchActive: $isSearchActive,
                    posterNamespace: posterNamespace,
                    viewModel: viewModel,
                    modelContainer: modelContext.container,
                    onLoadMore: loadMoreItems
                )

                if viewModel.showingNoteOverlay, let collectionID = viewModel.selectedCollectionID {
                    NoteOverlayView(viewModel: viewModel, collectionID: collectionID)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .animation(AppTheme.Animation.springGentle, value: isSearchActive)
            .navigationTitle(
                isSearchActive
                    ? "Search" : viewModel.navigationTitle(for: viewModel.selectedCategory)
            )
            .navigationDestination(for: MediaItem.self) { item in
                DetailView(item: item, namespace: posterNamespace) { actorName in
                    navigateToActorSearch(actorName)
                }
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let item = modelContext.model(for: id) as? MediaItem {
                    DetailView(item: item, namespace: posterNamespace) { actorName in
                        navigateToActorSearch(actorName)
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
            .onChange(of: MediaStateService.shared.needsSingleItemUpdateCount) { _, _ in
                if let itemID = MediaStateService.shared.lastChangedItemID {
                    updateSingleItemInContentView(id: itemID)
                }
            }
            .onChange(of: MediaStateService.shared.needsFullRefreshCount) { _, _ in
                viewModel.isLibraryMetadataDirty = true
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
                LibraryDetailToolbarContent(
                    viewModel: viewModel,
                    sidebarSelection: $sidebarSelection,
                    showingBulkManager: $showingBulkManager,
                    isSyncHovered: $isSyncHovered,
                    isSystemSmartCategory: isSystemSmartCategory,
                    modelContext: modelContext
                )
            }
            .background {
                Group {
                    Button("") { sidebarSelection = .category(.home) }.keyboardShortcut("1", modifiers: .command)
                    Button("") { sidebarSelection = .category(.discover) }.keyboardShortcut("2", modifiers: .command)
                    Button("") { sidebarSelection = .category(.upcoming) }.keyboardShortcut("3", modifiers: .command)
                    Button("") { sidebarSelection = .category(.all) }.keyboardShortcut("4", modifiers: .command)
                    Button("") { sidebarSelection = .category(.movie) }.keyboardShortcut("5", modifiers: .command)
                    Button("") { sidebarSelection = .category(.tvShow) }.keyboardShortcut("6", modifiers: .command)
                    Button("") { sidebarSelection = .category(.smartHub) }.keyboardShortcut("7", modifiers: .command)
                    Button("") { isSearchActive = true }.keyboardShortcut("f", modifiers: .command)
                }
                .opacity(0)
            }
        }
        .sheet(isPresented: $showingBulkManager) {
            if let collectionID = viewModel.selectedCollectionID,
               let collection = collections.first(where: { $0.id == collectionID }) {
                BulkCollectionManagerView(collection: collection)
            }
        }
        .task(priority: .userInitiated) {
            SleepManager.shared.purgeDataCache = {
                ImageCache.shared.clearMemoryCache()
                ImageCache.shared.clearDiskIndex()
                Task { await APIClient.shared.clearMemoryCaches() }
                TasteActor.clearCache()
                BadgeEngine.clearScanCache()
                URLCache.shared.removeAllCachedResponses()
            }
            performUpdate()
        }
        .onChange(of: SleepManager.shared.isAsleep) { _, isAsleep in
            if isAsleep {
                viewModel.purgeSleepCache()
            } else {
                Task { await DiscoveryHubCache.shared.invalidate() }
                viewModel.isLibraryMetadataDirty = true
                viewModel.filterSubject.send()
            }
        }
        .task(priority: .background) {
            guard !UserDefaults.standard.bool(forKey: UserDefaultsKeys.skipStartupTasks.rawValue) else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            checkAndRepairMissingMetadata()
            checkAndRepairStaleMetadata()
            
            // Phase 6: Genre Deconstruction Migration
            let migrated = UserDefaults.standard.bool(forKey: UserDefaultsKeys.genreDeconstructionV1.rawValue)
            if !migrated {
                let container = modelContext.container
                Task.detached(priority: .background) {
                    let service = BackgroundDataService(modelContainer: container)
                    await service.deepHealGenres()
                    UserDefaults.standard.set(true, forKey: "genre_deconstruction_v1")
                }
            }
        }
    }

    private func performUpdate() {
        // Skip updating if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        // Automatically heal stale "Coming Soon" items before sorting
        checkAndRepairStaleMetadata()

        let snapshot = FilterSnapshot(from: viewModel)

        updateTask?.cancel()
        updateTask = Task {
            // Optimization: Skip heavy data load if view handles its own data
            if snapshot.category == .discover || snapshot.category == .insights || snapshot.category == .upcoming || (snapshot.category == .smartHub && snapshot.collectionID == nil) { return }

            // Soft update preserves existing items to avoid flickering during background syncs
            let isSoftUpdate = !viewModel.displayedItems.isEmpty

            if !isSoftUpdate {
                // Reset pagination only for "Hard" updates to avoid flickering during background syncs
                await MainActor.run {
                    viewModel.displayedItems = []
                    viewModel.currentOffset = 0
                    viewModel.isLoadingMore = false
                }
            }

            do {
                let filterActor = getFilterActor()

                // Phase 4 Optimization: Pagination limit
                let limit = viewModel.pageSize
                let result = try await filterActor.filterAndSort(
                    category: snapshot.category,
                    searchText: snapshot.searchText,
                    sortOrder: snapshot.sortOrder,
                    network: snapshot.networks,
                    language: snapshot.language,
                    genre: snapshot.genre,
                    year: snapshot.year,
                    state: snapshot.state,
                    badge: nil,
                    groupBy: snapshot.groupBy,
                    collectionID: snapshot.collectionID,
                    limit: limit,
                    offset: 0
                )
                
                let allIDs: Set<String>
                let metadata: MediaFilterActor.LibraryMetadata?
                let shouldFetchMetadata = !isSoftUpdate && viewModel.isLibraryMetadataDirty
                if shouldFetchMetadata {
                    allIDs = (try? await filterActor.allLibraryTMDBIDs()) ?? []
                    metadata = try? await filterActor.fetchLibraryMetadata()
                } else {
                    allIDs = viewModel.libraryTMDBIDs
                    metadata = nil
                }

                if Task.isCancelled { return }

                await MainActor.run {
                    viewModel.totalItemCount = result.totalCount
                    viewModel.displayedItems = result.displayed
                    viewModel.featuredUpcomingItems = result.featuredUpcoming
                    viewModel.recentlyAddedItems = result.recentlyAdded
                    viewModel.homeContinueWatchingItems = result.homeContinueWatching
                    viewModel.spotlightHero = result.spotlightHero
                    viewModel.groupedItems = result.grouped

                    if shouldFetchMetadata {
                        viewModel.libraryTMDBIDs = allIDs
                        viewModel.isLibraryMetadataDirty = false
                        if let meta = metadata {
                            viewModel.cachedNetworks = meta.networks
                            viewModel.cachedGenres = meta.genres
                            viewModel.cachedLanguages = meta.languages
                        }
                    }

                    // Update Mood Theme based on current visible content
                    let moodColors = result.displayed.prefix(10).compactMap { $0.themeColorHex.flatMap { Color(hex: $0) } }
                    themeCoordinator.updateMood(for: Array(moodColors), colorScheme: colorScheme)

                    // Sync network/studio data on hard updates only
                    if !isSoftUpdate && (snapshot.category == .discover || snapshot.category == .all) {
                        let container = modelContext.container
                        Task.detached(priority: .background) {
                            let sync = DiscoverySyncService(modelContainer: container)
                            await sync.syncLibrary(force: false)
                        }
                    }
                }

                // Async Recommendation Calculation (Only for Home view)
                if snapshot.category == .home {
                    // Spread the load: Wait 2 seconds before heavy taste analytics
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if Task.isCancelled { return }

                    let tasteActor = TasteActor(modelContainer: modelContext.container)
                    let recs = await tasteActor.calculateRecommendations()

                    await MainActor.run {
                        // Find metadata for these IDs
                        self.viewModel.recommendations = recs.compactMap {
                            (id, reason) -> MediaThumbnailMetadata? in
                            guard let item = modelContext.model(for: id) as? MediaItem
                            else { return nil }
                            return MediaThumbnailMetadata(item: item, recommendationReason: reason)
                        }
                    }
                }
            } catch is CancellationError {
                // Task was cancelled, ignore.
            } catch {
                AppLogger.debug("Error filtering items: \(error)")
            }
        }
    }

    private func loadMoreItems() {
        guard !viewModel.isLoadingMore && viewModel.displayedItems.count < viewModel.totalItemCount
        else { return }

        viewModel.isLoadingMore = true
        let nextOffset = viewModel.displayedItems.count
        let snapshot = FilterSnapshot(from: viewModel)

        Task {
            do {
                let filterActor = getFilterActor()
                let result = try await filterActor.filterAndSort(
                    category: snapshot.category,
                    searchText: snapshot.searchText,
                    sortOrder: snapshot.sortOrder,
                    network: snapshot.networks,
                    language: snapshot.language,
                    genre: snapshot.genre,
                    year: snapshot.year,
                    state: snapshot.state,
                    badge: nil,
                    groupBy: snapshot.groupBy,
                    collectionID: snapshot.collectionID,
                    limit: viewModel.pageSize,
                    offset: nextOffset
                )

                await MainActor.run {
                    viewModel.displayedItems.append(contentsOf: result.displayed)
                    viewModel.isLoadingMore = false
                    viewModel.currentOffset = nextOffset
                }
            } catch {
                AppLogger.debug("Error loading more: \(error)")
                await MainActor.run { viewModel.isLoadingMore = false }
            }
        }
    }

    private func navigateToActorSearch(_ actorName: String) {
        viewModel.selectedCategory = .all
        viewModel.searchText = actorName
        viewModel.navigationPath = NavigationPath()
        isSearchActive = true
        viewModel.filterSubject.send()
    }

    private func checkAndRepairStaleMetadata() {
        let container = modelContext.container
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            let now = Date()
            let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.storedIsUpcoming == true && $0.cachedNextAiringDate != nil && $0.cachedNextAiringDate! < now })
            
            if let staleItems = try? context.fetch(descriptor), !staleItems.isEmpty {
                AppLogger.info("♻️ Auto-healing \(staleItems.count) stale items...", logger: AppLogger.background)
                for item in staleItems {
                    item.syncCachedProperties()
                }
                try? context.save()
                
                await MainActor.run {
                    MediaStateService.shared.postMediaStateChanged()
                }
            }
        }
    }

    private func checkAndRepairMissingMetadata() {
        let container = modelContext.container
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            
            var missingIDs = Set<String>()
            
            let p1 = #Predicate<MediaItem> { $0.overview == "" || $0.posterURL == nil }
            if let items = try? context.fetch(FetchDescriptor<MediaItem>(predicate: p1)) {
                missingIDs.formUnion(items.map { $0.id })
            }
            let p2 = #Predicate<MediaItem> { $0.lastUpdated == nil || $0.cachedWatchedEpisodeCount == nil }
            if let items = try? context.fetch(FetchDescriptor<MediaItem>(predicate: p2)) {
                missingIDs.formUnion(items.map { $0.id })
            }
            
            if !missingIDs.isEmpty {
                let idsArray = Array(missingIDs)
                await MainActor.run {
                    DataService.shared.refreshMetadata(forIDs: idsArray, modelContext: modelContext, force: true)
                }
            }
        }
    }

    private var isSystemSmartCategory: Bool {
        viewModel.selectedCategory.isSmartCategory
    }

    private func updateSingleItemInContentView(id: PersistentIdentifier) {
        let category = viewModel.selectedCategory
        let searchText = viewModel.searchText
        let networks = viewModel.selectedNetworks
        let language = viewModel.selectedLanguage
        let genre = viewModel.selectedGenre
        let year = viewModel.selectedYear
        let state = viewModel.selectedState
        let collectionID = viewModel.selectedCollectionID
        
        Task {
            do {
                let filterActor = getFilterActor()
                let updatedMetadata = try await filterActor.fetchMetadataIfMatches(
                    for: id,
                    category: category,
                    searchText: searchText,
                    network: networks,
                    language: language,
                    genre: genre,
                    year: year,
                    state: state,
                    collectionID: collectionID
                )
                
                await MainActor.run {
                    withAnimation(AppTheme.Animation.easeInOut) {
                        func updateList(_ list: inout [MediaThumbnailMetadata], updated: MediaThumbnailMetadata?) {
                            if let index = list.firstIndex(where: { $0.id == id }) {
                                if let updated = updated {
                                    list[index] = updated
                                } else {
                                    list.remove(at: index)
                                }
                            }
                        }
                        
                        updateList(&viewModel.displayedItems, updated: updatedMetadata)
                        updateList(&viewModel.recentlyAddedItems, updated: updatedMetadata)
                        updateList(&viewModel.homeContinueWatchingItems, updated: updatedMetadata)
                        updateList(&viewModel.featuredUpcomingItems, updated: updatedMetadata)
                        
                        if viewModel.spotlightHero?.id == id {
                            viewModel.spotlightHero = updatedMetadata
                        }
                        
                        for i in 0..<viewModel.groupedItems.count {
                            var itemsInGroup = viewModel.groupedItems[i].1
                            if let index = itemsInGroup.firstIndex(where: { $0.id == id }) {
                                if let updated = updatedMetadata {
                                    itemsInGroup[index] = updated
                                } else {
                                    itemsInGroup.remove(at: index)
                                }
                                viewModel.groupedItems[i].1 = itemsInGroup
                            }
                        }
                        
                        let moodColors = viewModel.displayedItems.prefix(10).compactMap { $0.themeColorHex.flatMap { Color(hex: $0) } }
                        themeCoordinator.updateMood(for: Array(moodColors), colorScheme: colorScheme)
                    }
                }
            } catch {
                AppLogger.debug("⚠️ Error updating single item optimistic UI in ContentView: \(error)")
            }
        }
    }
}

#Preview("Content View") {
    ContentView()
        .modelContainer(try! ModelContainer(
            for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
                 MediaCollection.self, StudioAliasEntity.self, NetworkEntity.self,
                 GenreEntity.self, LanguageEntity.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        ))
}
