import SwiftUI
import SwiftData

enum SortOrder: String, CaseIterable, Identifiable {
    case alphabetical = "Alphabetical"
    case newestRelease = "Newest Release"
    case recentlyAdded = "Recently Added"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .newestRelease: return "calendar"
        case .recentlyAdded: return "clock.badge.checkmark"
        }
    }
}

enum GroupBy: String, CaseIterable, Identifiable {
    case none = "None"
    case year = "Year"
    case category = "Category"
    
    var id: String { self.rawValue }
    
    var icon: String {
        switch self {
        case .none: return "square.grid.2x2"
        case .year: return "calendar.badge.clock"
        case .category: return "folder"
        }
    }
}

@Observable
class MediaViewModel {
    var selectedCategory: String? = "Home"
    var searchText: String = ""
    var navigationPath = NavigationPath()
    var searchSubmitTrigger: Int = 0
    
    // Per-category view settings
    var categorySortOrders: [String: SortOrder] = [:]
    var categoryGroupBys: [String: GroupBy] = [:]
    
    var currentSortOrder: SortOrder {
        let cat = selectedCategory ?? "All"
        return categorySortOrders[cat] ?? .alphabetical
    }
    
    var currentGroupBy: GroupBy {
        let cat = selectedCategory ?? "All"
        return categoryGroupBys[cat] ?? .none
    }

    var selectedNetwork: String? = nil
    var selectedLanguage: String? = nil
    var isBatchRefreshing: Bool = false
    var lastDiscoveryCalculationHash: Int = 0
    var gridResetID: UUID = UUID()
    var isInitialLoading: Bool = true // Track first load
    var discoveryRefreshTrigger: Int = 0 // NEW: Trigger for Discovery Hub refresh

    // Persistent Actors to prevent deinitialization warnings
    var filterActor: MediaFilterActor?
    var discoverySyncService: DiscoverySyncService?
    var tasteActor: TasteActor?

    // Pagination State
    var totalItemCount: Int = 0
    var currentOffset: Int = 0
    let pageSize: Int = 200
    var isLoadingMore: Bool = false
    var isFastScrolling: Bool = false

    // Process Data (Main Actor Cache) - NOW USING LIGHTWEIGHT METADATA
    var displayedItems: [MediaThumbnailMetadata] = []
    var recentlyAddedItems: [MediaThumbnailMetadata] = []
    var homeContinueWatchingItems: [MediaThumbnailMetadata] = []
    var groupedItems: [(String, [MediaThumbnailMetadata])] = []
    var recommendations: [MediaThumbnailMetadata] = []
    var featuredUpcomingItems: [MediaThumbnailMetadata] = []

    // Discovery Cache
    var cachedNetworks: [DiscoveryNode] = []
    var cachedGenres: [DiscoveryNode] = []
    var cachedLanguages: [DiscoveryNode] = []
    var forYouRecommendations: [MediaThumbnailMetadata] = []
    var lastDiscoveryRefresh: Date?

    // Trending Cache
    var trendingMovies: [MediaSearchResult] = []
    var trendingTV: [MediaSearchResult] = []

    func navigationTitle(for category: String?) -> String {
        if let network = selectedNetwork { return network }
        if let lang = selectedLanguage {
            return Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
        }
        if let cat = category, let type = MediaType(rawValue: cat) {
            return type.pluralName
        }
        if category == "Home" { return "Home" }
        if category == "InProgress" { return "In Progress" }
        if category == "Watchlist" { return "Watchlist" }
        if category == "Loved" { return "Loved" }
        if category == "Completed" { return "Completed" }
        if category == "Archive" { return "Archive" }
        if category == "Disliked" { return "Disliked" }
        if category == "Binge" { return "Binge" }
        if category == "Discover" { return "Discovery Hub" }
        if category == "Insights" { return "Taste Insights" }
        if category == "All" { return "Library" }
        return category ?? "Library"
    }
}

struct ContentView: View {
    @Namespace private var posterNamespace
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = MediaViewModel()
    @State private var themeCoordinator = AppThemeCoordinator.shared
    @State private var isSearchActive = false
    @State private var selectedHeroItem: MediaItem? = nil
    @State private var isSyncHovered = false
    
    @State private var updateTask: Task<Void, Never>?
    
    private func updateDisplayedItems(delay: UInt64 = 150_000_000) {
        // Skip updating if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        let capturedColorScheme: ColorScheme = colorScheme

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
            let network = viewModel.selectedNetwork
            let language = viewModel.selectedLanguage
            let groupBy = viewModel.currentGroupBy

            // Optimization: Skip heavy data load if moving to Discovery Hub
            if category == "Discover" { return }

            // Reset pagination for new filter/sort
            await MainActor.run {
                viewModel.currentOffset = 0
                viewModel.isLoadingMore = false
            }

            do {
                if viewModel.filterActor == nil {
                    viewModel.filterActor = MediaFilterActor(modelContainer: modelContext.container)
                }
                let filterActor = viewModel.filterActor!
                
                // Phase 4 Optimization: Pagination limit
                let limit = viewModel.pageSize
                
                let result = try await filterActor.filterAndSort(
                    category: category,
                    searchText: currentSearchText, 
                    sortOrder: sortOrder,
                    network: network,
                    language: language,
                    groupBy: groupBy,
                    limit: limit,
                    offset: 0
                )
                
                if Task.isCancelled { return }
                
                await MainActor.run {
                    viewModel.totalItemCount = result.totalCount
                    
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.displayedItems = result.displayed
                        viewModel.featuredUpcomingItems = result.featuredUpcoming
                        viewModel.recentlyAddedItems = result.recentlyAdded
                        viewModel.homeContinueWatchingItems = result.homeContinueWatching
                        viewModel.groupedItems = result.grouped
                    }
                    
                    // Allow UI to process data arrival before removing skeletons
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                        await MainActor.run {
                            viewModel.isInitialLoading = false
                        }
                    }
                    
                    // Update theme mood based on visible items
                    // Prioritize featured carousel if on Upcoming, or Continue Watching if on Home
                    if category == "Upcoming", let firstHero = result.featuredUpcoming.first {
                        let heroID = firstHero.id
                        if let item = modelContext.model(for: heroID) as? MediaItem,
                           !item.isDeleted,
                           let hex = item.themeColorHex,
                           let color = Color(hex: hex) {
                            themeCoordinator.updateMood(for: [color], colorScheme: capturedColorScheme)
                        }
                    } else if category == "Home", let firstHome = result.homeContinueWatching.first {
                        let heroID = firstHome.id
                        if let item = modelContext.model(for: heroID) as? MediaItem,
                           !item.isDeleted,
                           let hex = item.themeColorHex,
                           let color = Color(hex: hex) {
                            themeCoordinator.updateMood(for: [color], colorScheme: capturedColorScheme)
                        }
                    } else {
                        let visibleIDs = result.displayed.prefix(10).map { $0.id }
                        let visibleColors = visibleIDs.compactMap { id -> Color? in
                            guard let item = modelContext.model(for: id) as? MediaItem,
                                  !item.isDeleted,
                                  let hex = item.themeColorHex else { return nil }
                            return Color(hex: hex)
                        }
                        themeCoordinator.updateMood(for: visibleColors, colorScheme: capturedColorScheme)
                    }
                }
                
                // Async Recommendation Calculation (Only for Home view)
                if category == "Home" {
                    let tasteActor = TasteActor(modelContainer: modelContext.container)
                    let recs = await tasteActor.calculateRecommendations()

                    await MainActor.run {
                        // Find metadata for these IDs
                        self.viewModel.recommendations = recs.compactMap { (id, reason) -> MediaThumbnailMetadata? in
                            guard let item = modelContext.model(for: id) as? MediaItem, !item.isDeleted else { return nil }
                            return MediaThumbnailMetadata(
                                id: item.persistentModelID,
                                title: item.title,
                                posterURL: item.posterURL,
                                backdropURL: item.backdropURL,
                                overview: item.overview,
                                genres: item.cachedGenres,
                                releaseDate: item.releaseDate,
                                state: item.state,
                                type: item.type,
                                taste: item.tasteValue,
                                cachedNextAiringDate: item.cachedNextAiringDate,
                                cachedNetwork: item.cachedNetwork,
                                themeColorHex: item.themeColorHex,
                                badgeText: item.badgeText,
                                watchProgress: item.storedWatchProgressLabel,
                                nextEpisodeToWatchLabel: item.storedNextEpisodeLabel,
                                progress: item.storedProgress,
                                isUpcoming: item.storedIsUpcoming,
                                isBingeDrop: item.storedIsBingeDrop,
                                smartBadgeLabel: item.storedSmartBadgeLabel,
                                smartBadgeIcon: item.storedSmartBadgeIcon,
                                isSparkleBadge: item.storedSmartBadgeIsSparkle,
                                versionHash: item.lastStateChangeDate.hashValue,
                                recommendationReason: reason,
                                remainingCount: item.remainingEpisodesCount
                            )
                        }
                    }
                }
            } catch {
                print("Error filtering items: \(error)")
            }
        }
    }

    private func loadMoreItems() {
        guard !viewModel.isLoadingMore && viewModel.displayedItems.count < viewModel.totalItemCount else { return }
        
        viewModel.isLoadingMore = true
        let nextOffset = viewModel.displayedItems.count
        
        Task {
            let currentSearchText = viewModel.searchText
            let category = viewModel.selectedCategory
            let sortOrder = viewModel.currentSortOrder
            let network = viewModel.selectedNetwork
            let language = viewModel.selectedLanguage
            let groupBy = viewModel.currentGroupBy
            let limit = viewModel.pageSize

            do {
                let filterActor = MediaFilterActor(modelContainer: modelContext.container)
                let result = try await filterActor.filterAndSort(
                    category: category,
                    searchText: currentSearchText, 
                    sortOrder: sortOrder,
                    network: network,
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
                print("Error loading more items: \(error)")
                await MainActor.run { viewModel.isLoadingMore = false }
            }
        }
    }
    
    private func performLibrarySync() {
        // 1. Find items to sync (Visible items + recently added for speed, or all if small)
        let ids = viewModel.displayedItems.map { $0.id }
        let itemsToRefresh = ids.compactMap { modelContext.model(for: $0) as? MediaItem }
        
        if itemsToRefresh.isEmpty { return }
        
        viewModel.isBatchRefreshing = true
        
        // 2. Clear image cache to force-refresh posters/logos (as requested)
        ImageCache.shared.clearFullCache()
        
        // 3. Trigger metadata update
        DataService.shared.refreshMetadata(for: itemsToRefresh, modelContext: modelContext)
        
        Task {
            // Give network tasks a moment to start
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await MainActor.run {
                viewModel.isBatchRefreshing = false
                updateDisplayedItems()
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
                viewModel.selectedCategory = "All"
                viewModel.searchText = item.title
                viewModel.navigationPath = NavigationPath()
                updateDisplayedItems()
            }
        } else if viewModel.selectedCategory == "Discover" {
            DiscoveryHubView(namespace: posterNamespace, viewModel: viewModel) { filter in
                viewModel.navigationPath.append(filter)
            }
        } else if viewModel.selectedCategory == "Insights" {
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
                showingUpcomingOnly: viewModel.selectedCategory == "Upcoming",
                searchText: viewModel.searchText,
                selectedNetwork: viewModel.selectedNetwork,
                namespace: posterNamespace,
                isFastScrolling: $viewModel.isFastScrolling,
                onSelectHero: { _ in },
                onNetworkSelected: { network in
                    viewModel.selectedNetwork = network
                    updateDisplayedItems()
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
            SidebarNavigation(selection: $viewModel.selectedCategory)
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden) // Allow appBackground to show through sidebar
                .navigationTitle("Library")
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
                .onChange(of: viewModel.selectedCategory) {
                    viewModel.selectedNetwork = nil
                    viewModel.selectedLanguage = nil
                    viewModel.isInitialLoading = true // Reset loading state for category switch
                    updateDisplayedItems()
                }
        } detail: {
            NavigationStack(path: $viewModel.navigationPath) {
                mainContent
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isSearchActive)
                .navigationTitle(isSearchActive ? "Search" : viewModel.navigationTitle(for: viewModel.selectedCategory))
                .navigationDestination(for: MediaItem.self) { item in
                    DetailView(item: item, namespace: posterNamespace) { actorName in
                        viewModel.selectedCategory = "All" // Switch to All to check all titles
                        viewModel.searchText = actorName
                        viewModel.navigationPath = NavigationPath() // CLEAR NAVIGATION STACK
                        isSearchActive = true // ACTIVATE SEARCH VIEW
                        updateDisplayedItems()
                    }
                }
                .navigationDestination(for: DiscoveryFilter.self) { filter in
                    FilteredLibraryGridView(filter: filter, namespace: posterNamespace, isFastScrolling: $viewModel.isFastScrolling)
                }
                .searchable(text: $viewModel.searchText, isPresented: $isSearchActive, placement: .automatic, prompt: "Search movies & shows")
                .onSubmit(of: .search) {
                    viewModel.searchSubmitTrigger += 1
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
                        Button("") { viewModel.selectedCategory = "Home" }.keyboardShortcut("1", modifiers: .command)
                        Button("") { viewModel.selectedCategory = "Upcoming" }.keyboardShortcut("2", modifiers: .command)
                        Button("") { viewModel.selectedCategory = "InProgress" }.keyboardShortcut("3", modifiers: .command)
                        Button("") { viewModel.selectedCategory = "Watchlist" }.keyboardShortcut("4", modifiers: .command)
                        Button("") { viewModel.selectedCategory = "All" }.keyboardShortcut("5", modifiers: .command)
                        
                        Button("") { isSearchActive = true }
                            .keyboardShortcut("f", modifiers: .command)
                    }
                    .opacity(0)
                }
            }
            .sleepModeSupport()
        }
        .appBackground(network: viewModel.selectedNetwork, category: viewModel.selectedCategory) // Apply to the whole NavigationSplitView
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

    private func onNetworkSelected(_ network: String) {
        withAnimation {
            viewModel.selectedNetwork = network.isEmpty ? nil : network
            updateDisplayedItems()
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button {
            performLibrarySync()
        } label: {
            ZStack {
                Circle()
                    .fill(isSyncHovered ? Color.primary.opacity(0.1) : Color.clear)
                    .frame(width: 32, height: 32)
                
                if viewModel.isBatchRefreshing {
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
        .disabled(viewModel.isBatchRefreshing)
    }

    @ViewBuilder
    private var displaySettingsMenu: some View {
        let cat = viewModel.selectedCategory ?? "All"
        
        Menu {
            Picker("Sort By", selection: Binding(
                get: { viewModel.currentSortOrder },
                set: { viewModel.categorySortOrders[cat] = $0; updateDisplayedItems() }
            )) {
                ForEach(SortOrder.allCases) { order in
                    Label(order.rawValue, systemImage: order.icon)
                        .tag(order)
                }
            }
            
            Picker("Group By", selection: Binding(
                get: { viewModel.currentGroupBy },
                set: { viewModel.categoryGroupBys[cat] = $0; updateDisplayedItems() }
            )) {
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
        guard let cat = viewModel.selectedCategory else { return nil }
        return MediaType(rawValue: cat)
    }

    private var isSortable: Bool {
        guard let cat = viewModel.selectedCategory else { return false }
        if cat == "Discover" || cat == "Insights" { return false }
        return cat == "All" || cat == "InProgress" || cat == "Watchlist" || cat == "Loved" || cat == "Completed" || cat == "Binge" || MediaType(rawValue: cat) != nil
    }

    private var isRefreshable: Bool {
        guard let cat = viewModel.selectedCategory else { return false }
        // Discovery Hub has its own refreshable logic (pull to refresh)
        if cat == "Discover" || cat == "Insights" || cat == "Home" { return false }
        return true
    }
}

struct FilteredLibraryGridView: View {
    let filter: DiscoveryFilter
    let namespace: Namespace.ID
    @Binding var isFastScrolling: Bool
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @Environment(\.modelContext) private var modelContext
    
    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    let columns = [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)]
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(Array(items.indices), id: \.self) { idx in
                            let item = items[idx]
                            if !item.isDeleted {
                                NavigationLink(value: item) {
                                    MediaThumbnailView(item: item, mode: .grid, namespace: namespace, staggerIndex: idx, isFastScrolling: isFastScrolling)
                                }                            .buttonStyle(.interactive)
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                }
            }
            .padding(.vertical, 20)
        }
        .scrollClipDisabled()
        .navigationTitle(displayTitle)
        .appBackground(
            network: filter.type == .studio ? filter.name : nil,
            tint: filter.type != .studio ? appAccent.color : nil
        )
        .onAppear {
            fetchItems()
        }
    }

    private var displayTitle: String {
        switch filter.type {
        case .studio: return filter.name
        case .genre: return filter.name
        case .language: return LanguageUtils.languageName(for: filter.name)
        }
    }

    private func fetchItems() {
        let type = filter.type
        let name = filter.name
        
        let descriptor = FetchDescriptor<MediaItem>(
            sortBy: [SortDescriptor(\.releaseDate, order: .reverse)]
        )
        
        do {
            let all = try modelContext.fetch(descriptor)
            switch type {
            case .studio:
                items = all.filter { $0.cachedNetwork == name }
            case .genre:
                items = all.filter { $0.cachedGenres.contains(name) }
            case .language:
                items = all.filter { $0.cachedLanguage == name }
            }
            isLoading = false
        } catch {
            print("Error fetching filtered items: \(error)")
            isLoading = false
        }
    }
}
