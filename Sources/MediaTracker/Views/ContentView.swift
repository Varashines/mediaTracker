import SwiftData
import SwiftUI
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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
                    isSearchActive = false
                    Task { @MainActor in
                        viewModel.navigationPath = NavigationPath()

                        switch selection {
                        case .category(let category):
                            viewModel.filter.selectedCategory = category
                            viewModel.filter.resetFilters()
                            viewModel.collection.selectedCollectionID = nil
                        case .collection(let id, let name, _):
                            viewModel.filter.selectedCategory = .smartHub
                            viewModel.collection.selectedCollectionID = id
                            viewModel.collection.selectedCollectionName = name
                            viewModel.filter.resetFilters()
                        }

                        viewModel.filterSubject.send()

                        let container = modelContext.container
                        Task.detached(priority: .utility) { [viewModel] in
                            let actor = MediaFilterActor.shared(modelContainer: container)

                            let needsMetadata = await MainActor.run { viewModel.discovery.cachedGenres.isEmpty }

                            if needsMetadata {
                                let metadata = try? await actor.fetchLibraryMetadata()
                                await MainActor.run {
                                    if let meta = metadata {
                                        viewModel.discovery.cachedNetworks = meta.networks
                                        viewModel.discovery.cachedStudios = meta.studios
                                        viewModel.discovery.cachedGenres = meta.genres
                                        viewModel.discovery.cachedLanguages = meta.languages
                                        viewModel.discovery.cachedProviders = meta.providers
                                    }
                                }
                            }

                            if selection == .category(.discover) {
                                let allIDs = (try? await actor.allLibraryTMDBIDs()) ?? []
                                await MainActor.run {
                                    viewModel.display.libraryTMDBIDs = allIDs
                                }

                                try? await BackgroundOperationGate.shared.performSync(label: "navSync", container: container) {
                                    let sync = DiscoverySyncService(modelContainer: container)
                                    await sync.syncLibrary(force: false)
                                }
                            }
                        }
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
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: isSearchActive) { _, active in
            if !active {
                sidebarSelection = .category(viewModel.filter.selectedCategory)
            }
        }
        .onAppear {
            handleAppIntentLaunch()
        }
    }

    private func handleAppIntentLaunch() {
        if let query = UserDefaults.standard.string(forKey: "spotlight_search_query") {
            UserDefaults.standard.removeObject(forKey: "spotlight_search_query")
            viewModel.filter.selectedCategory = .all
            viewModel.filter.searchText = query
            isSearchActive = true
            viewModel.filterSubject.send()
        } else if let openID = UserDefaults.standard.string(forKey: "spotlight_open_id") {
            UserDefaults.standard.removeObject(forKey: "spotlight_open_id")
            NavigationRouter.shared.pendingSpotlightItemID = openID
        }
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
    
    @State private var showingBulkManager = false
    @State private var hasInitiallyLoaded = false
    @State private var refreshID = 0
    private let themeCoordinator = AppThemeCoordinator.shared
    @State private var updateTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?
    
    @AppStorage("has_seen_welcome") private var hasSeenWelcome = false
    @State private var showWelcome = false
    @State private var showImportSheet = false
    @State private var showDataRecoveryAlert = false
    @State private var recoveryLog: String?

    private func getFilterActor() -> MediaFilterActor {
        MediaFilterActor.shared(modelContainer: modelContext.container)
    }

    private var categoryMoodColor: Color {
        if isSearchActive { return .clear }
        return viewModel.filter.selectedCategory.moodColor
    }

    private var searchPlaceholder: String {
        switch viewModel.filter.searchTypeFilter {
        case .all: return "Search movies & shows"
        case .movie: return "Search movies"
        case .tvShow: return "Search TV shows"
        case .castCrew: return "Search cast & crew"
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

                Group {
                    if viewModel.collection.showingNoteOverlay, let collectionID = viewModel.collection.selectedCollectionID {
                        NoteOverlayView(viewModel: viewModel, collectionID: collectionID)
                            .if(!AppThemeCoordinator.isReducingVisualEffects) {
                                $0.transition(.move(edge: .top).combined(with: .opacity))
                            }
                    }
                }
                .zIndex(100)
                .animation(AppTheme.Animation.easeInOut, value: viewModel.collection.showingNoteOverlay)
            }
            .adaptiveBackground()
            .searchable(
                text: $viewModel.filter.searchText,
                isPresented: $isSearchActive,
                placement: .toolbar,
                prompt: searchPlaceholder
            )
            .onSubmit(of: .search) {
                let query = viewModel.filter.searchText.trimmingCharacters(in: .whitespaces)
                if query.count >= 2 {
                    var recent = (UserDefaults.standard.string(forKey: "recent_searches") ?? "")
                        .split(separator: "\n").map(String.init)
                    recent.removeAll { $0.lowercased() == query.lowercased() }
                    recent.insert(query, at: 0)
                    UserDefaults.standard.set(Array(recent.prefix(5)).joined(separator: "\n"), forKey: "recent_searches")
                }
            }
            .toolbarTitleMenuIfAvailable {
                Button("Home") {
                    viewModel.collection.selectedCollectionID = nil
                    viewModel.collection.selectedCollectionName = nil
                    viewModel.filter.selectedCategory = .home
                }
                Button("Discovery Hub") {
                    viewModel.collection.selectedCollectionID = nil
                    viewModel.collection.selectedCollectionName = nil
                    viewModel.filter.selectedCategory = .discover
                }
                Button("Release Calendar") {
                    viewModel.collection.selectedCollectionID = nil
                    viewModel.collection.selectedCollectionName = nil
                    viewModel.filter.selectedCategory = .upcoming
                }
                Divider()
                Button("Library") {
                    viewModel.collection.selectedCollectionID = nil
                    viewModel.collection.selectedCollectionName = nil
                    viewModel.filter.selectedCategory = .all
                }
                Button("Movies") {
                    viewModel.collection.selectedCollectionID = nil
                    viewModel.collection.selectedCollectionName = nil
                    viewModel.filter.selectedCategory = .movie
                }
                Button("TV Shows") {
                    viewModel.collection.selectedCollectionID = nil
                    viewModel.collection.selectedCollectionName = nil
                    viewModel.filter.selectedCategory = .tvShow
                }
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
                LibraryStatsActor.clearCache()
                guard hasInitiallyLoaded else { return }
                viewModel.filterSubject.send()
            }
            .task(id: viewModel.filter.searchText) {
                guard hasInitiallyLoaded else { return }
                viewModel.filterSubject.send()
            }
            .toolbar {

                LibraryDetailToolbarContent(
                    viewModel: viewModel,
                    sidebarSelection: $sidebarSelection,
                    showingBulkManager: $showingBulkManager,
                    isSystemSmartCategory: isSystemSmartCategory,
                    isSearchActive: isSearchActive,
                    modelContext: modelContext,
                    onRefresh: refreshAction
                )
            }
            .toolbar(sleepManager.isAsleep ? .hidden : .visible, for: .windowToolbar)
            .toolbarBackground(.hidden, for: .windowToolbar)
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
                    Button("") {
                        if !viewModel.navigationPath.isEmpty {
                            viewModel.navigationPath.removeLast()
                        } else if viewModel.collection.selectedCollectionID != nil {
                            viewModel.collection.selectedCollectionID = nil
                        } else if viewModel.filter.selectedCategory.isSmartCategory {
                            sidebarSelection = .category(.smartHub)
                        }
                    }.keyboardShortcut(.leftArrow, modifiers: .command)
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
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Collection not found")
                        .font(.headline)
                    Button("Close") { showingBulkManager = false }
                        .buttonStyle(.borderedProminent)
                }
                .frame(width: 300, height: 200)
            }
        }
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet {
                showImportSheet = true
            }
        }
        .sheet(isPresented: $showImportSheet) {
            ImportWizardSheet()
        }
        .alert("Data Lost", isPresented: $showDataRecoveryAlert) {
            Button("Copy Error & OK") {
                guard let logDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                      let logFiles = try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil),
                      let latestLog = logFiles.filter({ $0.pathExtension == "recovery.log" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first,
                      let logContent = try? String(contentsOf: latestLog, encoding: .utf8) else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(logContent, forType: .string)
            }
            Button("OK", role: .cancel) {}
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text("The database was corrupted and had to be rebuilt. Your library appears empty.\n\nTo restore, go to Settings → Vault → Import Library and select your latest backup.\n\nA backup of the old corrupted database was saved to your Application Support folder.")
                if let logContent = recoveryLog {
                    Divider()
                    Text("Error details:").font(.caption.weight(.semibold))
                    Text(logContent).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            if !hasSeenWelcome && !APIClient.shared.isTMDBConfigured {
                showWelcome = true
            }
            if AppErrorState.shared.storeRecoveredFromMigrationFailure {
                if let logDir = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
                   let logFiles = try? FileManager.default.contentsOfDirectory(at: logDir, includingPropertiesForKeys: nil),
                   let latestLog = logFiles.filter({ $0.pathExtension == "recovery.log" }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first {
                    recoveryLog = try? String(contentsOf: latestLog, encoding: .utf8)
                }
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
                URLCache.shared.removeAllCachedResponses()
            }
            viewModel.onFilterUpdate = {
                self.performUpdate()
                self.hasInitiallyLoaded = true
            }
            performUpdate()
        }
        .onChange(of: SleepManager.shared.isAsleep) { _, isAsleep in
            if isAsleep {
                viewModel.purgeSleepCache()
            } else {
                viewModel.filterSubject.send()
                checkAndRepairStaleMetadata()
            }
        }
        .onChange(of: NavigationRouter.shared.pendingSpotlightItemID) { _, newID in
            guard let id = newID else { return }
            NavigationRouter.shared.pendingSpotlightItemID = nil
            navigateToSpotlightItem(id)
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

            // Phase 8: Searchable language migration
            let languageMigrated = UserDefaults.standard.bool(forKey: UserDefaultsKeys.searchableLanguageV1.rawValue)
            if !languageMigrated {
                let container = modelContext.container
                Task.detached(priority: .background) {
                    try? await BackgroundOperationGate.shared.performHeal(label: "searchableLanguage", container: container) {
                        let service = BackgroundDataService(modelContainer: container)
                        try await service.performSearchableLanguageMigration()
                    }
                    UserDefaults.standard.set(true, forKey: UserDefaultsKeys.searchableLanguageV1.rawValue)
                }
            }
        }
    }

    private func performUpdate() {
        guard !SleepManager.shared.isAsleep else { return }

        let snapshot = FilterSnapshot(from: viewModel)

        updateTask?.cancel()
        updateTask = Task {
            if snapshot.category == .discover || snapshot.category == .insights || snapshot.category == .upcoming || (snapshot.category == .smartHub && snapshot.collectionID == nil) { return }

            let isSoftUpdate = !viewModel.display.displayedItems.isEmpty

            if !isSoftUpdate {
                await MainActor.run {
                    viewModel.display.displayedItems = []
                    viewModel.pagination.currentOffset = 0
                    viewModel.pagination.isLoadingMore = false
                }
            }

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
                    provider: snapshot.provider,
                    groupBy: snapshot.groupBy,
                    collectionID: snapshot.collectionID,
                    limit: viewModel.pagination.pageSize,
                    offset: 0
                )

                if Task.isCancelled { return }

                await MainActor.run {
                    viewModel.pagination.totalItemCount = result.totalCount
                    viewModel.display.applyFilterResult(result)
                }
            } catch is CancellationError {
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

        loadMoreTask?.cancel()
        loadMoreTask = Task {
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
                    provider: snapshot.provider,
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

                // Prefetch images for newly loaded items so they're ready when the user scrolls to them
                let posterURLs = result.displayed.compactMap { $0.posterURL }.compactMap { URL(string: $0) }
                if !posterURLs.isEmpty {
                    ImageCache.shared.prewarmImages(urls: posterURLs, targetSize: .thumbSmall)
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run { viewModel.pagination.isLoadingMore = false }
                    return
                }
                AppLogger.debug("Error loading more: \(error)")
                await MainActor.run { viewModel.pagination.isLoadingMore = false }
            }
        }
    }

    private func navigateToActorSearch(_ actorName: String) {
        viewModel.filter.resetFilters()
        viewModel.filter.selectedCategory = .all
        viewModel.filter.searchText = actorName
        viewModel.navigationPath = NavigationPath()
        isSearchActive = true
        viewModel.filterSubject.send()
    }

    private func navigateToSpotlightItem(_ identifier: String) {
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == identifier })
        descriptor.propertiesToFetch = MediaItem.thumbnailProperties
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        viewModel.navigationPath.append(item)
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
                    item.syncCachedProperties(dirty: .all)
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
            var desc1 = FetchDescriptor<MediaItem>(predicate: p1)
            desc1.fetchLimit = 100
            desc1.propertiesToFetch = [\.id]
            if let items = try? context.fetch(desc1) {
                missingIDs.formUnion(items.map { $0.id })
            }
            let p2 = #Predicate<MediaItem> { $0.lastUpdated == nil || $0.cachedWatchedEpisodeCount == nil }
            var desc2 = FetchDescriptor<MediaItem>(predicate: p2)
            desc2.fetchLimit = 100
            desc2.propertiesToFetch = [\.id]
            if let items = try? context.fetch(desc2) {
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
            return {
                ImageCache.shared.clearMemoryCache()
                viewModel.filterSubject.send()
            }
        }
    }

    private var isSystemSmartCategory: Bool {
        viewModel.filter.selectedCategory.isSmartCategory
    }

    private func updateSingleItemInContentView(id: PersistentIdentifier) {
        let category = viewModel.filter.selectedCategory

        // Home category has special processing (eligibility, sorting, limiting)
        // that single-item replacement cannot handle. Trigger a full refresh.
        if category == .home {
            viewModel.filterSubject.send()
            return
        }

        let searchText = viewModel.filter.searchText
        let networks = viewModel.filter.selectedNetworks
        let language = viewModel.filter.selectedLanguage
        let genre = viewModel.filter.selectedGenre
        let year = viewModel.filter.selectedYear
        let state = viewModel.filter.selectedState
        let provider = viewModel.filter.selectedProvider
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
                    provider: provider,
                    collectionID: collectionID
                )

                let newMoodColors = viewModel.display.displayedItems.prefix(10).compactMap { $0.themeColorHex.flatMap { Color(hex: $0) } }
                await MainActor.run {
                    viewModel.display.applyUpdate(updatedMetadata, id: id)
                    themeCoordinator.updateMood(for: Array(newMoodColors), colorScheme: colorScheme)
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
