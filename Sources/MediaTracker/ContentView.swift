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
                    if let selection = newValue {
                        // Reset navigation stack when switching categories
                        viewModel.navigationPath = NavigationPath()
                        
                        switch selection {
                        case .category(let category):
                            viewModel.selectedCategory = category
                            viewModel.selectedNetworks = nil
                            viewModel.selectedLanguage = nil
                            viewModel.selectedGenre = nil
                            viewModel.selectedYear = nil
                            viewModel.selectedState = nil
                            viewModel.isInitialLoading = true
                            
                            // Always clear collection ID when explicitly selecting a category
                            // especially when switching to 'smartHub' itself from the sidebar
                            viewModel.selectedCollectionID = nil
                        case .collection(let id, let name, _):
                            viewModel.selectedCategory = .smartHub
                            viewModel.selectedCollectionID = id
                            viewModel.selectedCollectionName = name
                            viewModel.selectedGenre = nil
                            viewModel.selectedYear = nil
                            viewModel.selectedState = nil
                            viewModel.isInitialLoading = true
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
        .animation(AppTheme.Animation.springDefault, value: viewModel.selectedCategory)
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
    @Query private var collections: [MediaCollection]
    
    @State private var isSyncHovered = false
    @State private var showingBulkManager = false
    @State private var themeCoordinator = AppThemeCoordinator.shared
    @State private var updateTask: Task<Void, Never>?

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
            .background(.ultraThinMaterial)
            .animation(AppTheme.Animation.springGentle, value: isSearchActive)
            .animation(AppTheme.Animation.springGentle, value: viewModel.selectedCategory)
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
            .onSubmit(of: .search) {
                viewModel.searchSubmitTrigger += 1
            }
            .onChange(of: MediaStateService.shared.needsFullRefreshCount) { _, _ in
                LibraryStatsActor.clearCache()
                let itemID = MediaStateService.shared.lastChangedItemID
                if let itemID = itemID {
                    updateSingleItemInContentView(id: itemID)
                } else {
                    viewModel.filterSubject.send()
                }
            }
            .task(id: viewModel.searchText) {
                viewModel.filterSubject.send()
            }
            .onReceive(viewModel.filterSubject.debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
                performUpdate()
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if !isSearchActive {
                        collectionNavigationToolbar
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !isSearchActive && isRefreshable {
                        refreshButton
                    }
                }
            }
            .background {
                KeyboardShortcutsView(sidebarSelection: $sidebarSelection, isSearchActive: $isSearchActive)
            }
        }
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
            
            // Phase 6: Genre Deconstruction Migration
            let migrated = UserDefaults.standard.bool(forKey: "genre_deconstruction_v1")
            if !migrated {
                let service = BackgroundDataService(modelContainer: modelContext.container)
                await service.deepHealGenres()
                UserDefaults.standard.set(true, forKey: "genre_deconstruction_v1")
            }
        }
    }

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
        let genre = viewModel.selectedGenre
        let year = viewModel.selectedYear
        let state = viewModel.selectedState
        let groupBy = viewModel.currentGroupBy
        let collectionID = viewModel.selectedCollectionID

        updateTask?.cancel()
        updateTask = Task {
            // Optimization: Skip heavy data load if moving to Discovery Hub
            if category == .discover || (category == .smartHub && collectionID == nil) { return }

            // Determine if this is a "Hard" update (category/filter change) vs a "Soft" update (data refresh)
            let isSoftUpdate = !viewModel.displayedItems.isEmpty && !viewModel.isInitialLoading

            if !isSoftUpdate {
                // Reset pagination only for "Hard" updates to avoid flickering during background syncs
                await MainActor.run {
                    viewModel.displayedItems = []
                    viewModel.currentOffset = 0
                    viewModel.isLoadingMore = false
                }
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
                    genre: genre,
                    year: year,
                    state: state,
                    badge: nil,
                    groupBy: groupBy,
                    collectionID: collectionID,
                    limit: limit,
                    offset: 0
                )
                
                let allIDs: Set<String>
                let metadata: MediaFilterActor.LibraryMetadata?
                if !isSoftUpdate {
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
                    viewModel.libraryTMDBIDs = allIDs
                    viewModel.isInitialLoading = false

                    if let meta = metadata {
                        viewModel.cachedNetworks = meta.networks
                        viewModel.cachedGenres = meta.genres
                        viewModel.cachedLanguages = meta.languages
                    }

                    // Update Mood Theme based on current visible content
                    let moodColors = result.displayed.prefix(10).compactMap { $0.themeColorHex.flatMap { Color(hex: $0) } }
                    themeCoordinator.updateMood(for: Array(moodColors), colorScheme: colorScheme)

                    // Sync network/studio data on hard updates only
                    if !isSoftUpdate && (category == .discover || category == .all) {
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
                            guard let item = modelContext.model(for: id) as? MediaItem
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
            let genre = viewModel.selectedGenre
            let year = viewModel.selectedYear
            let state = viewModel.selectedState
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
                    genre: genre,
                    year: year,
                    state: state,
                    badge: nil,
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

    private func navigateToActorSearch(_ actorName: String) {
        viewModel.selectedCategory = .all
        viewModel.searchText = actorName
        viewModel.navigationPath = NavigationPath()
        isSearchActive = true
        viewModel.filterSubject.send()
    }

    @ViewBuilder
    private var collectionNavigationToolbar: some View {
        if viewModel.selectedCollectionID != nil {
            HStack(spacing: AppTheme.Spacing.micro) {
                Button {
                    withAnimation {
                        sidebarSelection = .category(.smartHub)
                        viewModel.selectedCollectionID = nil
                    }
                    viewModel.filterSubject.send()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(AppTheme.Font.heading)
                }
                .help("Go Back")

                Button {
                    withAnimation(AppTheme.Animation.springSnappy) {
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
        } else if isSystemSmartCategory {
            Button {
                withAnimation {
                    sidebarSelection = .category(.smartHub)
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(AppTheme.Font.heading)
            }
            .help("Back to Smart Hub")
        }
    }

    private func checkAndRepairStaleMetadata() {
        let container = modelContext.container
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            let now = Date()
            let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.storedIsUpcoming == true && $0.cachedNextAiringDate != nil && $0.cachedNextAiringDate! < now })
            
            if let staleItems = try? context.fetch(descriptor), !staleItems.isEmpty {
                print("♻️ Auto-healing \(staleItems.count) stale items...")
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
                        .font(AppTheme.Font.heading)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(AppTheme.Animation.easeInOut) {
                isSyncHovered = hovering
            }
        }
        .help("Sync Library")
        .disabled(DataService.shared.isRefreshing)
    }

    private var isRefreshable: Bool {
        let cat = viewModel.selectedCategory
        if cat == .insights || cat == .home { return false }
        return true
    }
    
    private var isSystemSmartCategory: Bool {
        let cat = viewModel.selectedCategory
        return cat == .releaseRadar || cat == .smartUpcoming || cat == .catchUp || cat == .loved || cat == .binge || cat == .quickBites || cat == .stalled || cat == .archive
    }

    private func performLibrarySync() {
        guard !DataService.shared.isRefreshing else { return }

        let descriptor = FetchDescriptor<MediaItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }

        DataService.shared.refreshMetadata(for: items, modelContext: modelContext, force: true)
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
        
        let container = modelContext.container
        
        Task {
            do {
                let filterActor = MediaFilterActor(modelContainer: container)
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
                print("⚠️ Error updating single item optimistic UI in ContentView: \(error)")
            }
        }
    }
}

struct KeyboardShortcutsView: View {
    @Binding var sidebarSelection: SidebarItem?
    @Binding var isSearchActive: Bool
    
    var body: some View {
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
