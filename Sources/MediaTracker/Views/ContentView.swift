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
                .navigationTitle("Library")
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
                .onChange(of: sidebarSelection) { _, newValue in
                    guard let selection = newValue else { return }
                    Task { @MainActor in
                        viewModel.navigationPath = NavigationPath()

                        switch selection {
                        case .category(let category):
                            viewModel.filter.selectedCategory = category
                            viewModel.filter.selectedNetworks = nil
                            viewModel.filter.selectedLanguage = nil
                            viewModel.filter.selectedGenre = nil
                            viewModel.filter.selectedYear = nil
                            viewModel.filter.selectedState = nil

                            viewModel.collection.selectedCollectionID = nil
                        case .collection(let id, let name, _):
                            viewModel.filter.selectedCategory = .smartHub
                            viewModel.collection.selectedCollectionID = id
                            viewModel.collection.selectedCollectionName = name
                            viewModel.filter.selectedGenre = nil
                            viewModel.filter.selectedYear = nil
                            viewModel.filter.selectedState = nil
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
    }
}

struct LibraryDetailView: View {
    @Binding var sidebarSelection: SidebarItem?
    @Binding var isSearchActive: Bool
    var posterNamespace: Namespace.ID
    @Bindable var viewModel: MediaViewModel
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sleepManager) private var sleepManager
    @Query(sort: \MediaCollection.name) private var collections: [MediaCollection]
    
    @State private var isSyncHovered = false
    @State private var showingBulkManager = false
    @State private var refreshID = 0
    private let themeCoordinator = AppThemeCoordinator.shared
    @State private var updateTask: Task<Void, Never>?
    
    @AppStorage("has_seen_welcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @State private var showDataRecoveryAlert = false
    @AppStorage("theme_preference") private var themePreference = 0
    @AppStorage("custom_theme_palette") private var customThemePalette = 0

    private func getFilterActor() -> MediaFilterActor {
        MediaFilterActor.shared(modelContainer: modelContext.container)
    }

    private var categoryMoodColor: Color {
        if isSearchActive {
            return Color.clear
        }
        switch viewModel.filter.selectedCategory {
        case .home: return Color.clear
        case .discover: return Color.purple
        case .upcoming: return Color.orange
        case .all: return Color.clear
        case .movie: return Color.indigo
        case .tvShow: return Color.teal
        case .smartHub: return Color.purple
        case .insights: return Color.green
        case .releaseRadar: return Color.pink
        default: return Color.clear
        }
    }

    private var searchPlaceholder: String {
        switch viewModel.filter.searchTypeFilter {
        case .all: return "Search movies & shows"
        case .movie: return "Search movies"
        case .tvShow: return "Search TV shows"
        }
    }

    private var effectiveMoodColor: Color {
        themeCoordinator.categoryMoodColor == .clear ? categoryMoodColor : themeCoordinator.categoryMoodColor
    }
    
    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            ZStack {
                LibraryBackgroundView(mood: effectiveMoodColor)

                CategoryRouterView(
                    sidebarSelection: $sidebarSelection,
                    isSearchActive: $isSearchActive,
                    posterNamespace: posterNamespace,
                    viewModel: viewModel,
                    modelContainer: modelContext.container,
                    onLoadMore: loadMoreItems,
                    refreshID: refreshID
                )

                if viewModel.collection.showingNoteOverlay, let collectionID = viewModel.collection.selectedCollectionID {
                    NoteOverlayView(viewModel: viewModel, collectionID: collectionID)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(100)
                }
            }
            .adaptiveBackground()
            .searchable(
                text: $viewModel.filter.searchText,
                isPresented: $isSearchActive,
                placement: .toolbar,
                prompt: searchPlaceholder
            )
            .toolbarTitleMenuIfAvailable {
                Button("Home") { viewModel.filter.selectedCategory = .home }
                Button("Discovery Hub") { viewModel.filter.selectedCategory = .discover }
                Button("Release Calendar") { viewModel.filter.selectedCategory = .upcoming }
                Divider()
                Button("Library") { viewModel.filter.selectedCategory = .all }
                Button("Movies") { viewModel.filter.selectedCategory = .movie }
                Button("TV Shows") { viewModel.filter.selectedCategory = .tvShow }
            }
            .navigationTitle(
                sleepManager.isAsleep ? ""
                : viewModel.navigationTitle(for: viewModel.filter.selectedCategory)
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
                    isFastScrolling: $viewModel.pagination.isFastScrolling,
                    isSearchActive: $isSearchActive,
                    searchText: $viewModel.filter.searchText,
                    onNavigateToSearch: { name in navigateToActorSearch(name) })
            }
            .onChange(of: MediaStateService.shared.needsSingleItemUpdateCount) { _, _ in
                if let itemID = MediaStateService.shared.lastChangedItemID {
                    updateSingleItemInContentView(id: itemID)
                }
            }
            .onChange(of: MediaStateService.shared.needsFullRefreshCount) { _, _ in
                viewModel.display.isLibraryMetadataDirty = true
                LibraryStatsActor.clearCache()
                viewModel.filterSubject.send()
            }
            .task(id: viewModel.filter.searchText) {
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
                    isSearchActive: isSearchActive,
                    modelContext: modelContext,
                    onRefresh: refreshAction
                )
            }
            .toolbarBackground(sleepManager.isAsleep ? .hidden : .automatic, for: .windowToolbar)
            .toolbar(sleepManager.isAsleep ? .hidden : .visible, for: .windowToolbar)
            .background {
                Group {
                    Button("") { isSearchActive = true }.keyboardShortcut("f", modifiers: .command)
                    Button("") { sidebarSelection = .category(.home) }.keyboardShortcut("1", modifiers: .command)
                    Button("") { sidebarSelection = .category(.discover) }.keyboardShortcut("2", modifiers: .command)
                    Button("") { sidebarSelection = .category(.upcoming) }.keyboardShortcut("3", modifiers: .command)
                    Button("") { sidebarSelection = .category(.all) }.keyboardShortcut("4", modifiers: .command)
                    Button("") { sidebarSelection = .category(.movie) }.keyboardShortcut("5", modifiers: .command)
                    Button("") { sidebarSelection = .category(.tvShow) }.keyboardShortcut("6", modifiers: .command)
                    Button("") { sidebarSelection = .category(.smartHub) }.keyboardShortcut("7", modifiers: .command)
                    Button("") { viewModel.navigationPath.removeLast() }.keyboardShortcut(.leftArrow, modifiers: .command)
                    Button("") {
                        if !viewModel.filter.searchText.isEmpty {
                            viewModel.filter.searchText = ""
                        } else {
                            isSearchActive = false
                        }
                    }.keyboardShortcut(.escape, modifiers: [])
                }
                .opacity(0)
            }
        }
        .sheet(isPresented: $showingBulkManager) {
            if let collectionID = viewModel.collection.selectedCollectionID,
               let collection = collections.first(where: { $0.id == collectionID }) {
                BulkCollectionManagerView(collection: collection)
            }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet()
        }
        .alert("Data Lost", isPresented: $showDataRecoveryAlert) {
            Button("OK") {}
        } message: {
            Text("The database was corrupted and had to be rebuilt. Your library appears empty.\n\nTo restore, go to Settings → Vault → Import Library and select your latest backup.\n\nA backup of the old corrupted database was saved to your Application Support folder.")
        }
        .onAppear {
            if !hasSeenWelcome && !APIClient.shared.isTMDBConfigured {
                showWelcome = true
            }
            if AppErrorState.shared.storeRecoveredFromMigrationFailure {
                showDataRecoveryAlert = true
                AppErrorState.shared.storeRecoveredFromMigrationFailure = false
            }
        }
        .task(priority: .userInitiated) {
            SleepManager.shared.purgeDataCache = {
                ImageCache.shared.clearMemoryCache()
                ImageCache.shared.clearDiskIndex()
                Task { await APIClient.shared.clearMemoryCaches() }
                TasteActor.clearCache()
                BadgeEngine.clearScanCache()
                LibraryStatsActor.clearCache()
                PrefetchManager.shared.cancel()
                URLCache.shared.removeAllCachedResponses()
            }
            performUpdate()
        }
        .onChange(of: SleepManager.shared.isAsleep) { _, isAsleep in
            if isAsleep {
                viewModel.purgeSleepCache()
            } else {
                viewModel.display.isLibraryMetadataDirty = true
                viewModel.filterSubject.send()
                checkAndRepairStaleMetadata()
            }
        }
        .task(priority: .background) {
            guard !UserDefaults.standard.bool(forKey: UserDefaultsKeys.skipStartupTasks.rawValue) else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !SleepManager.shared.isAsleep else { return }
            checkAndRepairMissingMetadata()
            checkAndRepairStaleMetadata()
            
            // Phase 6: Genre Deconstruction Migration
            let migrated = UserDefaults.standard.bool(forKey: UserDefaultsKeys.genreDeconstructionV1.rawValue)
            if !migrated {
                let container = modelContext.container
                Task.detached(priority: .background) {
                    try? await BackgroundOperationGate.shared.performHeal(label: "genreMigration", container: container) {
                        let service = BackgroundDataService(modelContainer: container)
                        try await service.performLibraryHeal()
                    }
                    UserDefaults.standard.set(true, forKey: "genre_deconstruction_v1")
                }
            }
        }
    }

    private func performUpdate() {
        // Skip updating if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        let snapshot = FilterSnapshot(from: viewModel)

        updateTask?.cancel()
        updateTask = Task {
            // Optimization: Skip heavy data load if view handles its own data
            if snapshot.category == .discover || snapshot.category == .insights || snapshot.category == .upcoming || (snapshot.category == .smartHub && snapshot.collectionID == nil) { return }

            // Soft update preserves existing items to avoid flickering during background syncs
            let isSoftUpdate = !viewModel.display.displayedItems.isEmpty

            if !isSoftUpdate {
                // Reset pagination only for "Hard" updates to avoid flickering during background syncs
                await MainActor.run {
                    viewModel.display.displayedItems = []
                    viewModel.pagination.currentOffset = 0
                    viewModel.pagination.isLoadingMore = false
                }
            }

            do {
                let filterActor = getFilterActor()

                // Phase 4 Optimization: Pagination limit
                let limit = viewModel.pagination.pageSize
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
                let shouldFetchMetadata = !isSoftUpdate && viewModel.display.isLibraryMetadataDirty
                if shouldFetchMetadata {
                    allIDs = (try? await filterActor.allLibraryTMDBIDs()) ?? []
                    metadata = try? await filterActor.fetchLibraryMetadata()
                } else {
                    allIDs = viewModel.display.libraryTMDBIDs
                    metadata = nil
                }

                if Task.isCancelled { return }

                await MainActor.run {
                    viewModel.pagination.totalItemCount = result.totalCount
                    viewModel.display.displayedItems = result.displayed
                    viewModel.display.featuredUpcomingItems = result.featuredUpcoming
                    viewModel.display.recentlyAddedItems = result.recentlyAdded
                    viewModel.display.homeContinueWatchingItems = result.homeContinueWatching
                    viewModel.display.spotlightHero = result.spotlightHero
                    viewModel.display.groupedItems = result.grouped
                    viewModel.display.pickOfTheDay = result.pickOfTheDay

                    if shouldFetchMetadata {
                        viewModel.display.libraryTMDBIDs = allIDs
                        viewModel.display.isLibraryMetadataDirty = false
                        if let meta = metadata {
                            viewModel.discovery.cachedNetworks = meta.networks
                            viewModel.discovery.cachedGenres = meta.genres
                            viewModel.discovery.cachedLanguages = meta.languages
                        }
                    }

                    // Update Mood Theme based on current visible content
                    let moodColors = result.displayed.prefix(10).compactMap { $0.themeColorHex.flatMap { Color(hex: $0) } }
                    themeCoordinator.updateMood(for: Array(moodColors), colorScheme: colorScheme)

                    // Sync network/studio data on hard updates only
                    if !isSoftUpdate && (snapshot.category == .discover || snapshot.category == .all) {
                        let container = modelContext.container
                        Task.detached(priority: .background) {
                            try? await BackgroundOperationGate.shared.performSync(label: "navSync", container: container) {
                                let sync = DiscoverySyncService(modelContainer: container)
                                await sync.syncLibrary(force: false)
                            }
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
                        self.viewModel.display.recommendations = recs.compactMap {
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
        guard !viewModel.pagination.isLoadingMore && viewModel.display.displayedItems.count < viewModel.pagination.totalItemCount
        else { return }

        viewModel.pagination.isLoadingMore = true
        let nextOffset = viewModel.display.displayedItems.count
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
                    limit: viewModel.pagination.pageSize,
                    offset: nextOffset
                )

                await MainActor.run {
                    viewModel.display.displayedItems.append(contentsOf: result.displayed)
                    viewModel.pagination.isLoadingMore = false
                    viewModel.pagination.currentOffset = nextOffset
                }
            } catch {
                AppLogger.debug("Error loading more: \(error)")
                await MainActor.run { viewModel.pagination.isLoadingMore = false }
            }
        }
    }

    private func navigateToActorSearch(_ actorName: String) {
        viewModel.filter.selectedCategory = .all
        viewModel.filter.searchText = actorName
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
                    DataService.shared.refreshMetadata(forIDs: idsArray, modelContext: container.mainContext, force: true)
                }
            }
        }
    }

    private var refreshAction: () -> Void {
        switch viewModel.filter.selectedCategory {
        case .discover:
            return {
                ImageCache.shared.clearFullCache()
                viewModel.filter.discoveryRefreshTrigger += 1
            }
        case .upcoming:
            return { refreshID += 1 }
        case .insights:
            return { refreshID += 1 }
        case .smartHub where viewModel.collection.selectedCollectionID == nil:
            return { refreshID += 1 }
        default:
            return { viewModel.filterSubject.send() }
        }
    }

    private var isSystemSmartCategory: Bool {
        viewModel.filter.selectedCategory.isSmartCategory
    }

    private func updateSingleItemInContentView(id: PersistentIdentifier) {
        let category = viewModel.filter.selectedCategory
        let searchText = viewModel.filter.searchText
        let networks = viewModel.filter.selectedNetworks
        let language = viewModel.filter.selectedLanguage
        let genre = viewModel.filter.selectedGenre
        let year = viewModel.filter.selectedYear
        let state = viewModel.filter.selectedState
        let collectionID = viewModel.collection.selectedCollectionID
        
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
                        
                        updateList(&viewModel.display.displayedItems, updated: updatedMetadata)
                        updateList(&viewModel.display.recentlyAddedItems, updated: updatedMetadata)
                        updateList(&viewModel.display.homeContinueWatchingItems, updated: updatedMetadata)
                        updateList(&viewModel.display.featuredUpcomingItems, updated: updatedMetadata)
                        
                        if viewModel.display.spotlightHero?.id == id {
                            viewModel.display.spotlightHero = updatedMetadata
                        }
                        
                        for i in 0..<viewModel.display.groupedItems.count {
                            var itemsInGroup = viewModel.display.groupedItems[i].1
                            if let index = itemsInGroup.firstIndex(where: { $0.id == id }) {
                                if let updated = updatedMetadata {
                                    itemsInGroup[index] = updated
                                } else {
                                    itemsInGroup.remove(at: index)
                                }
                                viewModel.display.groupedItems[i].1 = itemsInGroup
                            }
                        }
                        
                        let moodColors = viewModel.display.displayedItems.prefix(10).compactMap { $0.themeColorHex.flatMap { Color(hex: $0) } }
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
