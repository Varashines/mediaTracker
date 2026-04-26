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

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $viewModel.selectedCategory)
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
                    Button("") {
                        isSearchActive = true
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0)
                }
            }
            .sleepModeSupport()
        }
        .appBackground(network: viewModel.selectedNetwork, category: viewModel.selectedCategory) // Apply to the whole NavigationSplitView
        .onReceive(NotificationCenter.default.publisher(for: .tasteWeightsChanged)) { _ in
            updateDisplayedItems(delay: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaStateChanged)) { _ in
            updateDisplayedItems(delay: 0)
        }
        .onAppear {
            NotificationManager.shared.requestPermission()
            
            // Priority 1: UI Hydration (Fetch 'Upcoming' immediately)
            updateDisplayedItems(delay: 0)

            // Priority 2: Delayed Maintenance (Wait 15 seconds for system to settle)
            let container = modelContext.container
            Task.detached(priority: .background) {
                // Wait for the user to finish looking at the initial launch screen
                try? await Task.sleep(nanoseconds: 15 * 1_000_000_000)
                
                // 1. Initial Discovery Sync
                let syncService = DiscoverySyncService(modelContainer: container)
                await syncService.syncLibrary(force: false)
                
                // 2. Migration: Ensure all smart badges and binge flags are computed
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<MediaItem>()
                if let items = try? context.fetch(descriptor) {
                    var itemsChanged = false
                    for item in items {
                        // FORCE SYNC: Ensure new Binge/BingeDrop logic runs for every item
                        item.syncCachedProperties()
                        itemsChanged = true
                        
                        if item.stateValue == "Wishlist" && item.state != .wishlist {
                            item.stateValue = item.state?.rawValue ?? "Wishlist"
                        }
                        if item.typeValue == "Movie" && item.type != .movie {
                            item.typeValue = item.type?.rawValue ?? "Movie"
                        }
                        
                        // Migration: Flatten network logo path
                        if item.type == .tvShow && item.cachedNetworkLogoPath == nil,
                           let logo = item.tvShowDetails?.networkLogoPath {
                            item.cachedNetworkLogoPath = logo
                        }
                    }
                    if itemsChanged {
                        try? context.save()
                        await MainActor.run { updateDisplayedItems() }
                    }
                }
                print("🏁 Delayed Background Maintenance Complete.")
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        let activeCat = viewModel.selectedCategory
        let isDiscover = activeCat == "Discover"
        let isInsights = activeCat == "Insights"
        let isHome = activeCat == "Home"
        let isLibrary = !isDiscover && !isInsights && !isHome
        
        ZStack(alignment: .top) {
            // 1. Home Stage
            Group {
                if isHome {
                    MediaGridView(
                        items: viewModel.displayedItems,
                        featuredCarouselItems: [],
                        recentlyAdded: viewModel.recentlyAddedItems,
                        homeContinueWatching: viewModel.homeContinueWatchingItems,
                        groupedItems: viewModel.groupedItems,
                        recommendations: viewModel.recommendations,
                        selectedCategory: "Home",
                        showingUpcomingOnly: false,
                        searchText: viewModel.searchText,
                        selectedNetwork: viewModel.selectedNetwork,
                        namespace: posterNamespace,
                        isFastScrolling: $viewModel.isFastScrolling,
                        onSelectHero: { metadata in navigate(to: metadata) },
                        onNetworkSelected: { onNetworkSelected($0) },
                        onLoadMore: { loadMoreItems() },
                        viewModel: viewModel
                    )
                }
            }
            .id("HomeStage")
            .modifier(PerspectiveDepthModifier(isActive: isHome))
            
            // 2. Library Stage (All / Movies / TV / Categories)
            Group {
                if isLibrary {
                    MediaGridView(
                        items: viewModel.displayedItems,
                        featuredCarouselItems: activeCat == "Upcoming" ? viewModel.featuredUpcomingItems : [],
                        recentlyAdded: viewModel.recentlyAddedItems,
                        homeContinueWatching: [],
                        groupedItems: viewModel.groupedItems,
                        recommendations: [],
                        selectedCategory: activeCat,
                        showingUpcomingOnly: activeCat == "Upcoming",
                        searchText: viewModel.searchText,
                        selectedNetwork: viewModel.selectedNetwork,
                        namespace: posterNamespace,
                        isFastScrolling: $viewModel.isFastScrolling,
                        onSelectHero: { metadata in navigate(to: metadata) },
                        onNetworkSelected: { onNetworkSelected($0) },
                        onLoadMore: { loadMoreItems() },
                        viewModel: viewModel
                    )
                }
            }
            .id("LibraryStage")
            .modifier(PerspectiveDepthModifier(isActive: isLibrary))
            
            // 3. Discovery Stage
            DiscoveryHubView(
                namespace: posterNamespace,
                viewModel: viewModel,
                onFilterSelected: { filter in
                    viewModel.navigationPath.append(filter)
                }
            )
            .id("DiscoverStage")
            .modifier(PerspectiveDepthModifier(isActive: isDiscover))

            // 4. Insights Stage
            InsightsView()
                .id("InsightsStage")
                .modifier(PerspectiveDepthModifier(isActive: isInsights))

            // 5. Dynamic Search Overlay
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
                .zIndex(100)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 1.1)).combined(with: .offset(y: 20)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            }
        }
        .background {
            // Fluid Background Morphing
            themeCoordinator.categoryMoodColor
                .animation(.smooth(duration: 0.8), value: viewModel.selectedCategory)
                .ignoresSafeArea()
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: viewModel.selectedCategory)
        .animation(.smooth(duration: 0.4), value: isSearchActive)
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

// Phase 2 Optimization: Sidebar Tokenization
@MainActor
struct SidebarView: View, Equatable {
    @Binding var selection: String?

    nonisolated static func == (lhs: SidebarView, rhs: SidebarView) -> Bool {
        // Compare projected values which are Sendable
        return lhs._selection.wrappedValue == rhs._selection.wrappedValue
    }

    var body: some View {
        List(selection: $selection) {
            Group {
                Label("Home", systemImage: "house.fill")
                    .tag("Home")

                Label("Upcoming", systemImage: "calendar")
                    .tag("Upcoming")

                Label("In Progress", systemImage: "play.circle")
                    .tag("InProgress")

                Label("Watchlist", systemImage: "list.bullet.rectangle")
                    .tag("Watchlist")

                Label("Library", systemImage: "tray.full")
                    .tag("All")
            }            .padding(.vertical, 4)

            Section("Smart Folders") {
                Label("Loved", systemImage: "heart.fill")
                    .tag("Loved")
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .tag("Completed")
                Label("Archive", systemImage: "archivebox")
                    .tag("Archive")
                Label("Disliked", systemImage: "hand.thumbsdown.fill")
                    .tag("Disliked")
                Label("Binge", systemImage: "rectangle.stack.fill")
                    .tag("Binge")
            }            .padding(.vertical, 4)
            
            Section("Explore") {
                Label("Discovery Hub", systemImage: "sparkles.tv")
                    .tag("Discover")
                
                Label("Insights", systemImage: "chart.bar.xaxis")
                    .tag("Insights")
            }
            .padding(.vertical, 4)
            
            Section("Categories") {
                ForEach(MediaType.allCases, id: \.self) { type in
                    let name = type.pluralName
                    let img = icon(for: type)
                    Label(name, systemImage: img)
                        .tag(type.rawValue)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func icon(for type: MediaType) -> String {
        switch type {
        case .movie: return "film"
        case .tvShow: return "tv"
        }
    }
}

struct MediaGridView: View {
    let items: [MediaThumbnailMetadata]
    let featuredCarouselItems: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let homeContinueWatching: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let recommendations: [MediaThumbnailMetadata]
    let selectedCategory: String?
    let showingUpcomingOnly: Bool
    let searchText: String
    let selectedNetwork: String?
    let namespace: Namespace.ID
    @Binding var isFastScrolling: Bool
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onNetworkSelected: (String) -> Void
    let onLoadMore: () -> Void
    var viewModel: MediaViewModel

    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @State private var visibleCount = 40 // Initial snappiness
    @State private var scrollTimer: Timer?
    
    @State private var upcomingScrollProgress: Double = 0
    @State private var upcomingScrollSpace = UUID().uuidString
    @State private var upcomingContentWidth: CGFloat = 0
    @State private var upcomingContainerWidth: CGFloat = 0

    @State private var continueWatchingScrollProgress: Double = 0
    @State private var continueWatchingScrollSpace = UUID().uuidString
    @State private var continueWatchingContentWidth: CGFloat = 0
    @State private var continueWatchingContainerWidth: CGFloat = 0

    @State private var forYouScrollProgress: Double = 0
    @State private var forYouScrollSpace = UUID().uuidString
    @State private var forYouContentWidth: CGFloat = 0
    @State private var forYouContainerWidth: CGFloat = 0

    var isCategoryPage: Bool {
        guard let cat = selectedCategory else { return false }
        return MediaType(rawValue: cat) != nil
    }

    var isMainSection: Bool {
        ["Home", "InProgress", "Watchlist", "All", "Archive", "Loved", "Completed", "Disliked", "Binge", "Upcoming"].contains(selectedCategory)
    }

    var body: some View {
        GeometryReader { mainGeo in
            let availableWidth = mainGeo.size.width
            let itemWidth: CGFloat = 160
            let spacing: CGFloat = 20
            let horizontalPadding: CGFloat = 30
            let usableWidth = availableWidth - (horizontalPadding * 2)
            let columnsCount = max(2, Int(usableWidth / (itemWidth + spacing)))
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columnsCount)

            ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                    if selectedCategory == "Home" && searchText.isEmpty && selectedNetwork == nil {
                        // Continue Watching (Top Carousel)
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(
                                title: "Continue Watching", 
                                icon: "play.fill", 
                                iconColor: .blue,
                                scrollProgress: homeContinueWatching.count > 1 ? continueWatchingScrollProgress : nil
                            )
                            
                            if !homeContinueWatching.isEmpty {
                                ScrollViewReader { proxy in
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 20) {
                                            Spacer(minLength: 10)
                                            ForEach(homeContinueWatching) { metadata in
                                                if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                                    NavigationLink(value: item) {
                                                        MediaThumbnailView(metadata: metadata, mode: .grid, namespace: namespace, isFastScrolling: isFastScrolling)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            Spacer(minLength: 10)
                                        }
                                        .padding(.vertical, 15)
                                        .background(
                                            GeometryReader { geo in
                                                let minX = geo.frame(in: .named(continueWatchingScrollSpace)).minX
                                                Color.clear
                                                    .preference(key: ScrollOffsetKey.self, value: [continueWatchingScrollSpace: minX])
                                                    .onAppear { continueWatchingContentWidth = geo.size.width }
                                                    .onChange(of: geo.size.width) { _, newValue in continueWatchingContentWidth = newValue }
                                            }
                                        )
                                    }
                                    .coordinateSpace(name: continueWatchingScrollSpace)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .onAppear { continueWatchingContainerWidth = geo.size.width }
                                                .onChange(of: geo.size.width) { _, newValue in continueWatchingContainerWidth = newValue }
                                        }
                                    )
                                    .onPreferenceChange(ScrollOffsetKey.self) { dict in
                                        guard let minX = dict[continueWatchingScrollSpace] else { return }
                                        let maxScroll = max(1, continueWatchingContentWidth - continueWatchingContainerWidth)
                                        let currentScroll = max(0, -minX)
                                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                                            continueWatchingScrollProgress = min(1.0, currentScroll / maxScroll)
                                        }
                                    }
                                    .scrollClipDisabled()
                                }
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(0..<6, id: \.self) { _ in
                                            MediaThumbnailPlaceholder(mode: .grid)
                                        }
                                    }
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 15)
                                }
                                .scrollClipDisabled()
                            }
                        }
                        .padding(.bottom, 20)

                        // Personalized For You (Middle Carousel)
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeader(
                                title: "For You", 
                                icon: "sparkles", 
                                iconColor: .yellow,
                                scrollProgress: recommendations.count > 1 ? forYouScrollProgress : nil
                            )
                            
                            if !recommendations.isEmpty {
                                ScrollViewReader { proxy in
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 24) {
                                            Spacer(minLength: 16)
                                            ForEach(recommendations) { metadata in
                                                if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                                    NavigationLink(value: item) {
                                                        HomeHeroCard(metadata: metadata, item: item, namespace: namespace, isFastScrolling: isFastScrolling)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                            Spacer(minLength: 16)
                                        }
                                        .padding(.vertical, 20)
                                        .background(
                                            GeometryReader { geo in
                                                let minX = geo.frame(in: .named(forYouScrollSpace)).minX
                                                Color.clear
                                                    .preference(key: ScrollOffsetKey.self, value: [forYouScrollSpace: minX])
                                                    .onAppear { forYouContentWidth = geo.size.width }
                                                    .onChange(of: geo.size.width) { _, newValue in forYouContentWidth = newValue }
                                            }
                                        )
                                    }
                                    .coordinateSpace(name: forYouScrollSpace)
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear
                                                .onAppear { forYouContainerWidth = geo.size.width }
                                                .onChange(of: geo.size.width) { _, newValue in forYouContainerWidth = newValue }
                                        }
                                    )
                                    .onPreferenceChange(ScrollOffsetKey.self) { dict in
                                        guard let minX = dict[forYouScrollSpace] else { return }
                                        let maxScroll = max(1, forYouContentWidth - forYouContainerWidth)
                                        let currentScroll = max(0, -minX)
                                        withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                                            forYouScrollProgress = min(1.0, currentScroll / maxScroll)
                                        }
                                    }
                                    .scrollClipDisabled()
                                }
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 24) {
                                        ForEach(0..<3, id: \.self) { _ in
                                            HomeHeroCardPlaceholder()
                                        }
                                    }
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 20)
                                }
                                .scrollClipDisabled()
                            }
                        }
                        .padding(.bottom, 20)
                    }

                // 2. Eager Featured Carousel (Upcoming View)
                if showingUpcomingOnly && searchText.isEmpty && selectedNetwork == nil && !featuredCarouselItems.isEmpty {
                    VStack(alignment: .leading, spacing: 15) {
                        SectionHeader(
                            title: "Featured",
                            icon: nil,
                            iconColor: .primary,
                            scrollProgress: featuredCarouselItems.count > 1 ? upcomingScrollProgress : nil
                        )
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(featuredCarouselItems) { metadata in
                                    if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                        NavigationLink(value: item) {
                                            MediaThumbnailView(metadata: metadata, mode: .hero, isUpcomingSection: true, namespace: namespace, isFastScrolling: isFastScrolling)
                                                .id(metadata.versionHash)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 30)
                            .padding(.vertical, 20)
                            .background(
                                GeometryReader { geo in
                                    let minX = geo.frame(in: .named(upcomingScrollSpace)).minX
                                    Color.clear
                                        .preference(key: ScrollOffsetKey.self, value: [upcomingScrollSpace: minX])
                                        .onAppear { upcomingContentWidth = geo.size.width }
                                        .onChange(of: geo.size.width) { _, newValue in upcomingContentWidth = newValue }
                                }
                            )
                        }
                        .coordinateSpace(name: upcomingScrollSpace)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onAppear { upcomingContainerWidth = geo.size.width }
                                    .onChange(of: geo.size.width) { _, newValue in upcomingContainerWidth = newValue }
                            }
                        )
                        .onPreferenceChange(ScrollOffsetKey.self) { dict in
                            guard let minX = dict[upcomingScrollSpace] else { return }
                            let maxScroll = max(1, upcomingContentWidth - upcomingContainerWidth)
                            let currentScroll = max(0, -minX)
                            withAnimation(.interactiveSpring(response: 0.35, dampingFraction: 0.85)) {
                                upcomingScrollProgress = min(1.0, currentScroll / maxScroll)
                            }
                        }
                    }
                    .compositingGroup()
                }
                
                VStack(alignment: .leading, spacing: 15) {
                    // Header Logic
                    if let network = selectedNetwork {
                        SectionHeader(title: network, icon: "tv", iconColor: appAccent.color)
                            .overlay(alignment: .trailing) {
                                Button { withAnimation { onNetworkSelected("") } } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 40)
                            }
                    } else if !isCategoryPage && !isMainSection && selectedCategory != "Discover" {
                        SectionHeader(title: selectedCategory ?? "Library", icon: "folder", iconColor: .secondary)
                    } else if selectedCategory == "Upcoming" {
                        SectionHeader(title: "Queue", icon: "list.bullet.indent", iconColor: .secondary)
                            .padding(.bottom, 10)
                    }
                    
                    if items.isEmpty && groupedItems.isEmpty {
                        if viewModel.isInitialLoading {
                            // Section-Aware Grid Skeletons
                            VStack(alignment: .leading, spacing: 25) {
                                if selectedCategory == "Home" {
                                    SectionHeader(title: "Coming Soon", icon: "calendar", iconColor: .secondary)
                                } else {
                                    SectionHeader(title: "Loading Library...", icon: "hourglass", iconColor: .secondary)
                                }
                                
                                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                    ForEach(0..<12, id: \.self) { _ in
                                        MediaThumbnailPlaceholder(mode: .grid)
                                    }
                                }
                                .padding(.horizontal, 30)
                            }
                            .padding(.top, 10)
                        } else {
                            LibraryEmptyStateView(category: selectedCategory) {
                                withAnimation {
                                    viewModel.selectedCategory = "Discover"
                                }
                            }
                        }
                    } else {

                        // 2. Eager Recently Added Row (Always Ready)
                        if selectedCategory == "All" && searchText.isEmpty && selectedNetwork == nil {
                            VStack(alignment: .leading, spacing: 15) {
                                SectionHeader(title: "Recently Added", icon: "clock.badge.checkmark", iconColor: .orange)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(recentlyAdded) { metadata in
                                            if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                                NavigationLink(value: item) {
                                                    MediaThumbnailView(metadata: metadata, mode: .grid, isFastScrolling: isFastScrolling).id(metadata.versionHash)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 30)
                                    .padding(.vertical, 15)
                                }
                                .scrollClipDisabled()
                            }
                            .compositingGroup()
                            Divider().padding(.horizontal, 30).padding(.bottom, 20)
                        }

                        // 3. Main Collection with Chunking & Pagination
                        if viewModel.currentGroupBy == .none && selectedCategory != "Archive" && selectedCategory != "Home" && selectedCategory != "Binge" {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                let baseItems = showingUpcomingOnly ? Array(items.dropFirst(featuredCarouselItems.count)) : items
                                
                                ForEach(baseItems.indices, id: \.self) { idx in
                                    let metadata = baseItems[idx]
                                    if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                        NavigationLink(value: item) {
                                            MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: !isCategoryPage, isUpcomingSection: showingUpcomingOnly, namespace: namespace, staggerIndex: idx, isFastScrolling: isFastScrolling)
                                                .id(metadata.versionHash)
                                                .entranceStagger(index: idx)
                                                .onAppear {
                                                    // Phase 4: Infinite Scroll Trigger
                                                    let lastID = items.last?.id
                                                    if metadata.id == lastID {
                                                        onLoadMore()
                                                    }
                                                }
                                        }
                                        .buttonStyle(.plain)
                                        .draggable(item.id)
                                    }
                                }
                            }
                            .padding(.horizontal, 30)
                            .padding(.top, 20)
                            .padding(.bottom, 40)
                        } else {
                            // Grouped View
                            VStack(alignment: .leading, spacing: 60) {
                                ForEach(groupedItems, id: \.0) { (key, groupMetadatas) in
                                    VStack(alignment: .leading, spacing: 25) {
                                        SectionHeader(
                                            title: key,
                                            icon: (key == "Coming Soon" && selectedCategory == "Home") ? "calendar" : nil,
                                            iconColor: .secondary
                                        )
                                        
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                            ForEach(groupMetadatas) { metadata in
                                                if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                                                    NavigationLink(value: item) {
                                                        MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: viewModel.currentGroupBy != .category, isUpcomingSection: showingUpcomingOnly, namespace: namespace, isFastScrolling: isFastScrolling)
                                                            .id(metadata.versionHash)
                                                            .entranceStagger(index: 0) // Simplified stagger for grouped
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 30)
                                        .padding(.top, 10)
                                    }
                                }
                            }
                            .padding(.bottom, 40)
                        }
                    }
                }
            }
            .padding(.vertical, 20)
            .background {
                GeometryReader { geo in
                    let currentY = geo.frame(in: .global).minY
                    Color.clear
                        .onChange(of: currentY) { oldValue, newValue in
                            let velocity = abs(newValue - oldValue)
                            if velocity > 30 && !isFastScrolling {
                                isFastScrolling = true
                            }
                            
                            scrollTimer?.invalidate()
                            scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                                Task { @MainActor in
                                    withAnimation(.smooth) {
                                        isFastScrolling = false
                                    }
                                }
                            }
                        }
                }
            }
        }
        .scrollClipDisabled()
        .onAppear { visibleCount = 40 }
        .onChange(of: items.count) { visibleCount = 40 }
        }
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
                                }                            .buttonStyle(.plain)
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
