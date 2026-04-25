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
    var sortOrder: SortOrder = .alphabetical
    var selectedGroupBy: GroupBy = .none
    var selectedNetwork: String? = nil
    var selectedLanguage: String? = nil
    var isBatchRefreshing: Bool = false
    var lastDiscoveryCalculationHash: Int = 0
    var gridResetID: UUID = UUID()

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
            let sortOrder = viewModel.sortOrder
            let network = viewModel.selectedNetwork
            let language = viewModel.selectedLanguage
            let groupBy = viewModel.selectedGroupBy

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
                    
                    // Update theme mood based on visible items
                    // Prioritize featured carousel if on Upcoming, or Continue Watching if on Home
                    if category == "Upcoming", let firstHero = result.featuredUpcoming.first {
                        let heroID = firstHero.id
                        if let item = modelContext.model(for: heroID) as? MediaItem,
                           let hex = item.themeColorHex,
                           let color = Color(hex: hex) {
                            themeCoordinator.updateMood(for: [color], colorScheme: capturedColorScheme)
                        }
                    } else if category == "Home", let firstHome = result.homeContinueWatching.first {
                        let heroID = firstHome.id
                        if let item = modelContext.model(for: heroID) as? MediaItem,
                           let hex = item.themeColorHex,
                           let color = Color(hex: hex) {
                            themeCoordinator.updateMood(for: [color], colorScheme: capturedColorScheme)
                        }
                    } else {
                        let visibleIDs = result.displayed.prefix(10).map { $0.id }
                        let visibleColors = visibleIDs.compactMap { id -> Color? in
                            guard let item = modelContext.model(for: id) as? MediaItem,
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
                            guard let item = modelContext.model(for: id) as? MediaItem else { return nil }
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
                                recommendationReason: reason
                            )
                        }
                    }
                }            } catch {
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
            let sortOrder = viewModel.sortOrder
            let network = viewModel.selectedNetwork
            let language = viewModel.selectedLanguage
            let groupBy = viewModel.selectedGroupBy
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
    
    private func performBatchRefresh() {
        // Find actual MediaItems from the metadata IDs
        let ids = viewModel.displayedItems.map { $0.id }
        let itemsToRefresh = ids.compactMap { modelContext.model(for: $0) as? MediaItem }
        
        viewModel.isBatchRefreshing = true
        
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

    private func performMetadataRefresh() {
        // Refresh EVERYTHING in the library, but only metadata
        let descriptor = FetchDescriptor<MediaItem>()
        let itemsToRefresh = (try? modelContext.fetch(descriptor)) ?? []
        
        viewModel.isBatchRefreshing = true
        
        DataService.shared.refreshMetadata(for: itemsToRefresh, modelContext: modelContext, metadataOnly: true)
        
        Task {
            // Give network tasks a moment to start
            try? await Task.sleep(nanoseconds: 2_000_000_000)
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
                        if !isSearchActive && isSortable {
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
                
                // 2. Migration: Ensure stateValue and typeValue are populated for existing items
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<MediaItem>()
                if let items = try? context.fetch(descriptor) {
                    var itemsChanged = false
                    for item in items {
                        if item.stateValue == "Wishlist" && item.state != .wishlist {
                            item.stateValue = item.state?.rawValue ?? "Wishlist"
                            itemsChanged = true
                        }
                        if item.typeValue == "Movie" && item.type != .movie {
                            item.typeValue = item.type?.rawValue ?? "Movie"
                            itemsChanged = true
                        }
                        // Migration: Flatten network logo path
                        if item.type == .tvShow && item.cachedNetworkLogoPath == nil,
                           let logo = item.tvShowDetails?.networkLogoPath {
                            item.cachedNetworkLogoPath = logo
                            itemsChanged = true
                        }
                        
                        // Re-calculate all stored UI fields if missing or for migration
                        if item.storedNextEpisodeLabel == nil && item.type == .tvShow {
                            item.syncCachedProperties()
                            itemsChanged = true
                        }
                        // Force recalculate upcoming flag to ensure correct category placement
                        if item.storedIsUpcoming != item.calculateIsUpcoming {
                            item.storedIsUpcoming = item.calculateIsUpcoming
                            item.syncCachedProperties()
                            itemsChanged = true
                        }
                    }
                    if itemsChanged {
                        try? context.save()
                    }
                }
                print("🏁 Delayed Background Maintenance Complete.")
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        let isDiscover = viewModel.selectedCategory == "Discover"
        let isInsights = viewModel.selectedCategory == "Insights"
        
        ZStack(alignment: .top) {
            // 1. Permanent Library Stage
            MediaGridView(
                items: viewModel.displayedItems, 
                featuredCarouselItems: viewModel.selectedCategory == "Upcoming" ? viewModel.featuredUpcomingItems : [],
                recentlyAdded: viewModel.recentlyAddedItems,
                homeContinueWatching: viewModel.homeContinueWatchingItems,
                groupedItems: viewModel.groupedItems,
                recommendations: viewModel.recommendations,
                selectedCategory: viewModel.selectedCategory, 
                showingUpcomingOnly: viewModel.selectedCategory == "Upcoming",
                searchText: viewModel.searchText,
                groupBy: viewModel.selectedGroupBy,
                selectedNetwork: viewModel.selectedNetwork,
                namespace: posterNamespace,
                isFastScrolling: $viewModel.isFastScrolling,
                onSelectHero: { metadata in
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        if let item = modelContext.model(for: metadata.id) as? MediaItem {
                            viewModel.navigationPath.append(item)
                        }
                    }
                },
                onNetworkSelected: { network in
                    withAnimation {
                        viewModel.selectedNetwork = network.isEmpty ? nil : network
                        updateDisplayedItems()
                    }
                },
                onLoadMore: {
                    loadMoreItems()
                }
            )
            .id("LibraryStage")
            .opacity(isSearchActive ? 0 : ((isDiscover || isInsights) ? 0 : 1))
            .scaleEffect((isDiscover || isInsights) ? 0.98 : 1.0)
            .offset(y: (isDiscover || isInsights) ? -10 : 0)
            .allowsHitTesting(!isSearchActive && !isDiscover && !isInsights)
            .zIndex((isDiscover || isInsights) ? 0 : 1)
            .clipped()
            
            // 2. Permanent Discovery Stage
            DiscoveryHubView(
                namespace: posterNamespace,
                viewModel: viewModel,
                onFilterSelected: { filter in
                    viewModel.navigationPath.append(filter)
                }
            )
            .id("DiscoverStage")
            .opacity(isSearchActive ? 0 : (isDiscover ? 1 : 0))
            .scaleEffect(isDiscover ? 1.0 : 1.02)
            .offset(y: isDiscover ? 0 : 15)
            .allowsHitTesting(!isSearchActive && isDiscover)
            .zIndex(isDiscover ? 1 : 0)
            .clipped()

            // 3. Permanent Insights Stage
            InsightsView()
                .id("InsightsStage")
                .opacity(isSearchActive ? 0 : (isInsights ? 1 : 0))
                .scaleEffect(isInsights ? 1.0 : 1.02)
                .offset(y: isInsights ? 0 : 15)
                .allowsHitTesting(!isSearchActive && isInsights)
                .zIndex(isInsights ? 1 : 0)
                .clipped()

            // 4. Dynamic Search Overlay
            if isSearchActive {
                SearchView(
                    searchText: $viewModel.searchText,
                    isSearchActive: $isSearchActive,
                    submitTrigger: viewModel.searchSubmitTrigger,
                    initialType: currentMediaType
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
        .background(themeCoordinator.categoryMoodColor)
        .animation(.smooth(duration: 0.45), value: viewModel.selectedCategory)
        .animation(.smooth(duration: 0.4), value: isSearchActive)
    }

    @ViewBuilder
    private var refreshButton: some View {
        Menu {
            Button {
                performBatchRefresh()
            } label: {
                Label("Refresh Library", systemImage: "arrow.clockwise")
            }
            
            Button {
                performMetadataRefresh()
            } label: {
                Label("Refresh All Metadata", systemImage: "bolt.fill")
            }
        } label: {
            if viewModel.isBatchRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(viewModel.isBatchRefreshing)
    }

    @ViewBuilder
    private var displaySettingsMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(SortOrder.allCases) { order in
                    Button {
                        viewModel.sortOrder = order
                        updateDisplayedItems()
                    } label: {
                        Label(order.rawValue, systemImage: order.icon)
                    }
                }
            }
            
            Section("Group By") {
                ForEach(GroupBy.allCases) { group in
                    Button {
                        viewModel.selectedGroupBy = group
                        updateDisplayedItems()
                    } label: {
                        Label(group.rawValue, systemImage: group.icon)
                    }
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
        if cat == "Discover" { return false }
        return cat == "All" || MediaType(rawValue: cat) != nil
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

private func availableStates(for item: MediaItem) -> [MediaState] {
    item.availableStates
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
    let groupBy: GroupBy
    let selectedNetwork: String?
    let namespace: Namespace.ID
    @Binding var isFastScrolling: Bool
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onNetworkSelected: (String) -> Void
    let onLoadMore: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var visibleCount = 40 // Initial snappiness
    @State private var scrollTimer: Timer?

    var isCategoryPage: Bool {
        guard let cat = selectedCategory else { return false }
        return MediaType(rawValue: cat) != nil
    }

    var isMainSection: Bool {
        ["Home", "InProgress", "Watchlist", "All", "Archive", "Loved", "Completed", "Disliked"].contains(selectedCategory)
    }

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)]

        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // 1. Home Dashboard Sections
                if selectedCategory == "Home" && searchText.isEmpty && selectedNetwork == nil {
                    // Personalized For You (Top Carousel)
                    if !recommendations.isEmpty {
                        HeroCarousel(title: "For You", icon: "sparkles", iconColor: .yellow, recommendations: recommendations, namespace: namespace, isFastScrolling: isFastScrolling)
                            .padding(.bottom, 20)
                    }

                    // Continue Watching (Middle Carousel)
                    if !homeContinueWatching.isEmpty {
                        ShelfCarousel(title: "Continue Watching", icon: "play.fill", iconColor: .blue, items: homeContinueWatching, namespace: namespace, isFastScrolling: isFastScrolling)
                            .padding(.bottom, 20)
                    }
                }

                // 2. Eager Featured Carousel (Upcoming View)
                if showingUpcomingOnly && searchText.isEmpty && selectedNetwork == nil && !featuredCarouselItems.isEmpty {                    VStack(alignment: .leading, spacing: 15) {
                        Text("Featured")
                            .font(.system(size: 28, weight: .bold))
                            .padding(.horizontal, 30)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 20) {
                                ForEach(featuredCarouselItems) { metadata in
                                    if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                        NavigationLink(value: item) {
                                            MediaThumbnailView(metadata: metadata, mode: .hero, isUpcomingSection: true, namespace: namespace, isFastScrolling: isFastScrolling)
                                                .id(metadata.versionHash)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                    }
                    .compositingGroup()
                }
                
                VStack(alignment: .leading, spacing: 15) {
                    // Header Logic
                    if let network = selectedNetwork {
                        HStack {
                            Text(network)
                                .font(.system(size: 24, weight: .bold))
                            Button { withAnimation { onNetworkSelected("") } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 30)
                    } else if !isCategoryPage && !isMainSection && selectedCategory != "Upcoming" && selectedCategory != "Discover" {
                        Text(selectedCategory ?? "Library").font(.system(size: 24, weight: .bold)).padding(.horizontal, 30)
                    } else if selectedCategory == "Upcoming" {
                        Text("Queue").font(.system(size: 24, weight: .bold)).padding(.horizontal, 30)
                    }
                    
                    if items.isEmpty && groupedItems.isEmpty {
                        LibraryEmptyStateView(category: selectedCategory)
                    } else {
                        // 2. Eager Recently Added Row (Always Ready)
                        if selectedCategory == "All" && searchText.isEmpty && selectedNetwork == nil {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Recently Added").font(.system(size: 24, weight: .bold)).padding(.horizontal, 30)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(recentlyAdded) { metadata in
                                            if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                                NavigationLink(value: item) {
                                                    MediaThumbnailView(metadata: metadata, mode: .grid, isFastScrolling: isFastScrolling).id(metadata.versionHash)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 30)
                                }
                            }
                            .compositingGroup()
                            Divider().padding(.horizontal, 30).padding(.bottom, 20)
                        }

                        // 3. Main Collection with Chunking & Pagination
                        if groupBy == .none && selectedCategory != "Archive" && selectedCategory != "Home" {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                let baseItems = showingUpcomingOnly ? Array(items.dropFirst(min(items.count, 5))) : items
                                
                                ForEach(baseItems.indices, id: \.self) { idx in
                                    let metadata = baseItems[idx]
                                    if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                        NavigationLink(value: item) {
                                            MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: !isCategoryPage, isUpcomingSection: showingUpcomingOnly, namespace: namespace, staggerIndex: idx, isFastScrolling: isFastScrolling)
                                                .id(metadata.versionHash)
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
                            .drawingGroup() // Metal Layer Flattening for VRAM efficiency
                            .padding(.horizontal, 30)
                            .padding(.bottom, 40)
                        } else {
                            // Grouped View
                            VStack(alignment: .leading, spacing: 60) {
                                ForEach(groupedItems, id: \.0) { (key, groupMetadatas) in
                                    VStack(alignment: .leading, spacing: 25) {
                                        if key == "Coming Soon" && selectedCategory == "Home" {
                                            HStack(spacing: 12) {
                                                Image(systemName: "calendar")
                                                    .foregroundStyle(.secondary)
                                                Text("Coming Soon")
                                            }
                                            .font(.system(size: 28, weight: .black))
                                            .padding(.horizontal, 30)
                                        } else {
                                            Text(key).font(.title2.bold()).foregroundStyle(.secondary).padding(.horizontal, 30)
                                        }
                                        
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                            ForEach(groupMetadatas) { metadata in
                                                if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                                    NavigationLink(value: item) {
                                                        MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: groupBy != .category, isUpcomingSection: showingUpcomingOnly, namespace: namespace, isFastScrolling: isFastScrolling)
                                                            .id(metadata.versionHash)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 30)
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
                            NavigationLink(value: item) {
                                MediaThumbnailView(item: item, mode: .grid, namespace: namespace, staggerIndex: idx, isFastScrolling: isFastScrolling)
                            }                            .buttonStyle(.plain)
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
        case .genre: return "\(filter.name) Movies & Shows"
        case .language: return "\(LanguageUtils.languageName(for: filter.name)) Titles"
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
