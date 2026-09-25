import SwiftData
import SwiftUI
import Combine

/// Pre-search view state for Esc-close restore (choice 3C+4A).
private struct SearchRestoreSnapshot {
    let sidebarSelection: SidebarItem?
    let navigationPath: NavigationPath
    let category: NavigationCategory
    let collectionID: UUID?
    let collectionName: String?
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Namespace private var posterNamespace
    @State private var viewModel = MediaViewModel()
    @State private var sidebarSelection: SidebarItem? = .category(.home)
    @State private var isSearchActive = false
    @State private var searchRestoreSnapshot: SearchRestoreSnapshot?
    @State private var pendingSearchRestore = false

    private func captureSearchRestoreSnapshot() {
        guard searchRestoreSnapshot == nil else { return }
        searchRestoreSnapshot = SearchRestoreSnapshot(
            sidebarSelection: sidebarSelection,
            navigationPath: viewModel.navigationPath,
            category: viewModel.filter.selectedCategory,
            collectionID: viewModel.collection.selectedCollectionID,
            collectionName: viewModel.collection.selectedCollectionName
        )
    }

    private func beginEscapeCloseSearch() {
        pendingSearchRestore = true
        isSearchActive = false
    }

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
                            // Resolve smartness once per selection change instead of
                            // per toolbar render (cached in CollectionState).
                            viewModel.collection.isSmartCollection =
                                (try? modelContext.fetch(
                                    FetchDescriptor<MediaCollection>(predicate: #Predicate { $0.id == id })
                                ).first?.isSmart) ?? false
                            viewModel.filter.resetFilters()
                        case .yearReview:
                            break
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
                viewModel: viewModel,
                onCaptureSearchSnapshot: captureSearchRestoreSnapshot,
                onEscapeCloseSearch: beginEscapeCloseSearch
            )
        }
        .navigationSplitViewStyle(.automatic)
        .frame(minWidth: 900, minHeight: 600)
        .onChange(of: isSearchActive) { _, active in
            if active {
                captureSearchRestoreSnapshot()
            } else if pendingSearchRestore, let snap = searchRestoreSnapshot {
                // Esc-close (3C): restore pre-search sidebar + path + category + collection.
                pendingSearchRestore = false
                searchRestoreSnapshot = nil
                viewModel.navigationPath = snap.navigationPath
                viewModel.filter.selectedCategory = snap.category
                viewModel.collection.selectedCollectionID = snap.collectionID
                viewModel.collection.selectedCollectionName = snap.collectionName
                sidebarSelection = snap.sidebarSelection
                viewModel.filterSubject.send()
            } else {
                // Non-Esc close (sidebar nav, etc.): keep prior reset behavior.
                searchRestoreSnapshot = nil
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
    var onCaptureSearchSnapshot: () -> Void = {}
    var onEscapeCloseSearch: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sleepManager) private var sleepManager
    @State private var showingBulkManager = false
    @State private var hasInitiallyLoaded = false
    @State private var refreshID = 0
    private let themeCoordinator = AppThemeCoordinator.shared
    @State private var updateTask: Task<Void, Never>?
    @State private var loadMoreTask: Task<Void, Never>?
    @State private var homeRefreshTask: Task<Void, Never>?

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
                     onCloseSearch: onEscapeCloseSearch,
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
                    isSearchActive: $isSearchActive,
                    searchText: $viewModel.filter.searchText,
                    onNavigateToSearch: { name in navigateToActorSearch(name) })
            }
            .background {
                // Leaf task: keystroke-driven filter sends live in a child so
                // LibraryDetailView body doesn't restart per character.
                SearchFilterTrigger(
                    searchText: viewModel.filter.searchText,
                    isSearchActive: isSearchActive,
                    hasInitiallyLoaded: hasInitiallyLoaded
                ) {
                    viewModel.filterSubject.send()
                }
                // Observation isolation: reading the invalidation counters in a leaf
                // child instead of onChange expressions on the root keeps every
                // MediaStateService tick from re-evaluating the whole LibraryDetailView tree.
                MediaStateLeafObserver(
                    onSingleItemUpdate: { itemID in
                        updateSingleItemInContentView(id: itemID)
                    },
                    onFullRefresh: {
                        // LibraryStatsActor.clearCache runs only in
                        // MediaStateService's debounced derived path — skip duplicates.
                        guard hasInitiallyLoaded else { return }
                        viewModel.filterSubject.send()
                    },
                    onTasteChange: {
                        let actor = getFilterActor()
                        viewModel.fetchRecommendationsIfNeeded(actor: actor, forceRefresh: true)
                    },
                    onRecommendationsRefreshed: {
                        let actor = getFilterActor()
                        viewModel.fetchRecommendationsIfNeeded(actor: actor, forceRefresh: false)
                    }
                )
                GlobalKeyboardShortcuts(
                    isSearchActive: $isSearchActive,
                    sidebarSelection: $sidebarSelection,
                    viewModel: viewModel,
                    onEscapeCloseSearch: onEscapeCloseSearch
                )
            }
            .toolbar {

                LibraryDetailToolbarContent(
                    viewModel: viewModel,
                    sidebarSelection: $sidebarSelection,
                    showingBulkManager: $showingBulkManager,
                    isSystemSmartCategory: isSystemSmartCategory,
                    isSearchActive: isSearchActive,
                    onRefresh: refreshAction
                )
            }
            .toolbarMaterial(isSleeping: sleepManager.isAsleep)
        }
        .sheet(isPresented: $showingBulkManager) {
            BulkCollectionSheet(
                collectionID: viewModel.collection.selectedCollectionID,
                isPresented: $showingBulkManager
            )
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
            }
        }
        .onChange(of: NavigationRouter.shared.pendingSpotlightItemID) { _, newID in
            guard let id = newID else { return }
            NavigationRouter.shared.pendingSpotlightItemID = nil
            navigateToSpotlightItem(id)
        }
        .onChange(of: NavigationRouter.shared.pendingCategory) { _, newCategory in
            guard let category = newCategory else { return }
            NavigationRouter.shared.pendingCategory = nil
            withAnimation(AppTheme.Animation.springSnappy) {
                sidebarSelection = .category(category)
            }
        }
        .onDisappear {
            updateTask?.cancel()
            updateTask = nil
            loadMoreTask?.cancel()
            loadMoreTask = nil
            homeRefreshTask?.cancel()
            homeRefreshTask = nil
        }
    }

    private func performUpdate() {
        guard !SleepManager.shared.isAsleep else { return }

        let snapshot = FilterSnapshot(from: viewModel)

        updateTask?.cancel()
        updateTask = Task {
            if snapshot.category == .discover || snapshot.category == .insights || snapshot.category == .upcoming || (snapshot.category == .smartHub && snapshot.collectionID == nil) { return }

            let isSoftUpdate = !viewModel.display.displayedItems.isEmpty
                || (snapshot.category == .home && (!viewModel.display.homeContinueWatchingItems.isEmpty || !viewModel.display.groupedItems.isEmpty))

            if !isSoftUpdate {
                await MainActor.run {
                    viewModel.display.displayedItems = []
                    viewModel.pagination.isLoadingMore = false
                    viewModel.pagination.isInitialLoad = true
                }
            }

            do {
                let filterActor = getFilterActor()
                let libraryVersion = MediaStateService.shared.libraryChangeToken
                let payloadVersion = MediaStateService.shared.fullRefreshToken
                let result = try await filterActor.filterAndSort(
                    category: snapshot.category,
                    searchText: snapshot.searchText,
                    sortOrder: snapshot.sortOrder,
                    network: snapshot.networks,
                    language: snapshot.languages,
                    genre: snapshot.genres,
                    year: snapshot.years,
                    state: snapshot.states,
                    badge: nil,
                    provider: snapshot.providers,
                    groupBy: snapshot.groupBy,
                    collectionID: snapshot.collectionID,
                    limit: viewModel.pagination.pageSize,
                    offset: 0,
                    libraryVersion: libraryVersion,
                    payloadVersion: payloadVersion
                )

                if Task.isCancelled { return }

                await MainActor.run {
                    viewModel.pagination.totalItemCount = result.totalCount
                    viewModel.pagination.isInitialLoad = false
                    viewModel.display.applyFilterResult(result)
                }


            } catch is CancellationError {
                // The replacement update task owns isInitialLoad now — resetting
                // here could clear the skeleton the new task just raised.
            } catch {
                AppLogger.debug("Error filtering items: \(error)")
                await MainActor.run {
                    viewModel.pagination.isInitialLoad = false
                    AppErrorState.shared.surfaceError("Couldn't load your library — try refreshing")
                }
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
                let libraryVersion = MediaStateService.shared.libraryChangeToken
                let payloadVersion = MediaStateService.shared.fullRefreshToken
                let result = try await filterActor.filterAndSort(
                    category: snapshot.category,
                    searchText: snapshot.searchText,
                    sortOrder: snapshot.sortOrder,
                    network: snapshot.networks,
                    language: snapshot.languages,
                    genre: snapshot.genres,
                    year: snapshot.years,
                    state: snapshot.states,
                    badge: nil,
                    provider: snapshot.providers,
                    groupBy: snapshot.groupBy,
                    collectionID: snapshot.collectionID,
                    limit: viewModel.pagination.pageSize,
                    offset: nextOffset,
                    pageOnly: true,
                    libraryVersion: libraryVersion,
                    payloadVersion: payloadVersion
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    viewModel.display.displayedItems.append(contentsOf: result.displayed)
                    viewModel.pagination.isLoadingMore = false
                }

                // Keep the next viewport warm without creating network work for an entire page.
                ImageCache.shared.prewarmImages(
                    result.displayed,
                    limit: 12,
                    targetSize: .thumbSmall,
                    priority: .low
                )
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run { viewModel.pagination.isLoadingMore = false }
                    return
                }
                AppLogger.debug("Error loading more: \(error)")
                await MainActor.run {
                    viewModel.pagination.isLoadingMore = false
                    AppErrorState.shared.surfaceError("Couldn't load more titles")
                }
            }
        }
    }

    private func navigateToActorSearch(_ actorName: String) {
        // Snapshot BEFORE wiping so Esc-restore returns to the prior view (3C+4A).
        onCaptureSearchSnapshot()
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

        // Home has special processing (eligibility, sorting, limiting) that
        // single-item replacement cannot handle — but a full re-query per tick
        // thrashes during metadata sync. Coalesce into one refresh per quiet window.
        if category == .home {
            scheduleDebouncedHomeRefresh()
            return
        }

        // Drop any cached search payload for this row so the next keystroke
        // re-reads updated searchable fields without wiping the whole cache.
        if let item = modelContext.model(for: id) as? MediaItem {
            let stringID = item.id
            Task {
                await getFilterActor().invalidateSearchPayload(for: stringID)
            }
        }

        let searchText = viewModel.filter.searchText
        let networks = viewModel.filter.selectedNetworks
        let languages = viewModel.filter.selectedLanguages
        let genres = viewModel.filter.selectedGenres
        let years = viewModel.filter.selectedYears
        let states = viewModel.filter.selectedStates
        let providers = viewModel.filter.selectedProviders
        let collectionID = viewModel.collection.selectedCollectionID

        Task {
            do {
                let filterActor = getFilterActor()
                let updatedMetadata = try await filterActor.fetchMetadataIfMatches(
                    for: id,
                    category: category,
                    searchText: searchText,
                    network: networks,
                    language: languages,
                    genre: genres,
                    year: years,
                    state: states,
                    provider: providers,
                    collectionID: collectionID
                )

                await MainActor.run {
                    viewModel.display.applyUpdate(updatedMetadata, id: id)
                    // Compute mood from the post-update list — the pre-update
                    // prefix(10) was reading stale rows.
                    let newMoodColors = viewModel.display.displayedItems
                        .prefix(10)
                        .compactMap { $0.themeColorHex.flatMap { Color(hex: $0) } }
                    themeCoordinator.updateMood(for: Array(newMoodColors), colorScheme: colorScheme)
                }
            } catch {
                AppLogger.debug("⚠️ Error updating single item optimistic UI in ContentView: \(error)")
            }
        }
    }

    /// Debounced full Home re-query — home eligibility can't be patched in place,
    /// but rapid single-item ticks (episode marks / metadata sync) must not each
    /// run a full pipeline pass.
    private func scheduleDebouncedHomeRefresh() {
        homeRefreshTask?.cancel()
        homeRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            viewModel.filterSubject.send()
        }
    }
}

private struct BulkCollectionSheet: View {
    @Query(sort: \MediaCollection.name) private var collections: [MediaCollection]
    let collectionID: UUID?
    @Binding var isPresented: Bool

    var body: some View {
        Group {
            if let collectionID, let collection = collections.first(where: { $0.id == collectionID }) {
                BulkCollectionManagerView(collection: collection)
            } else {
                LibraryEmptyStateView(
                    title: "Collection not found",
                    icon: "exclamationmark.triangle",
                    description: "This collection may have been deleted.",
                    actionLabel: "Close",
                    action: { isPresented = false }
                )
                .frame(width: 320, height: 280)
            }
        }
    }
}

private struct GlobalKeyboardShortcuts: View {
    @Binding var isSearchActive: Bool
    @Binding var sidebarSelection: SidebarItem?
    @Bindable var viewModel: MediaViewModel
    var onEscapeCloseSearch: () -> Void = {}

    var body: some View {
        Group {
            Button("") { isSearchActive = true }.keyboardShortcut("f", modifiers: .command)
            if !isSearchActive {
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
            }
            Button("") {
                guard isSearchActive else { return }
                if !viewModel.filter.searchText.isEmpty {
                    viewModel.filter.searchText = ""
                } else {
                    onEscapeCloseSearch()
                }
            }.keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
    }
}

/// Leaf that owns the keystroke → filterSubject `.task(id:)` so task restart
/// is scoped to this subtree. Parent still reads `searchText` for `.searchable`
/// and when constructing this view — full body isolation is not achieved here.
private struct SearchFilterTrigger: View {
    let searchText: String
    let isSearchActive: Bool
    let hasInitiallyLoaded: Bool
    let onSend: () -> Void

    var body: some View {
        EmptyView()
            .task(id: searchText) {
                guard hasInitiallyLoaded else { return }
                // Overlay search is SearchViewModel's authority — don't also
                // run the full library pipeline per keystroke.
                guard !isSearchActive else { return }
                onSend()
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
