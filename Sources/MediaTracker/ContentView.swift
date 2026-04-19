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
    var selectedCategory: String? = "Upcoming"
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

    // Processed Data (Main Actor Cache) - NOW USING LIGHTWEIGHT METADATA
    var displayedItems: [MediaThumbnailMetadata] = []
    var recentlyAddedItems: [MediaThumbnailMetadata] = []
    var groupedItems: [(String, [MediaThumbnailMetadata])] = []

    // Discovery Cache
    var cachedNetworks: [DiscoveryNode] = []
    var cachedGenres: [DiscoveryNode] = []
    var cachedLanguages: [DiscoveryNode] = []
    var lastDiscoveryRefresh: Date?

    func navigationTitle(for category: String?) -> String {
        if let network = selectedNetwork { return network }
        if let lang = selectedLanguage {
            return Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
        }
        if let cat = category, let type = MediaType(rawValue: cat) {
            return type.pluralName
        }
        if category == "NowWatching" { return "Now Watching" }
        if category == "InProgress" { return "In Progress" }
        if category == "OnHold" { return "On Hold" }
        if category == "Dropped" { return "Dropped" }
        if category == "Rewatching" { return "Re-watching" }
        if category == "Discover" { return "Discover" }
        if category == "All" { return "Library" }
        return category ?? "Library"
    }
}

struct ContentView: View {
    @Namespace private var posterNamespace
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.title) private var allItems: [MediaItem]
    @State private var viewModel = MediaViewModel()
    @State private var isSearchActive = false
    @State private var selectedHeroItem: MediaItem? = nil
    
    @State private var updateTask: Task<Void, Never>?
    
    private func updateDisplayedItems(delay: UInt64 = 50_000_000) {
        // Skip updating if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }
        
        updateTask?.cancel()
        updateTask = Task {
            // Give a tiny buffer for rapid changes (like typing or toggling filters)
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            
            let category = viewModel.selectedCategory
            let searchText = viewModel.searchText
            let sortOrder = viewModel.sortOrder
            let network = viewModel.selectedNetwork
            let language = viewModel.selectedLanguage
            let groupBy = viewModel.selectedGroupBy
            
            do {
                let filterActor = MediaFilterActor(modelContainer: modelContext.container)
                let result = try await filterActor.filterAndSort(
                    category: category,
                    searchText: searchText,
                    sortOrder: sortOrder,
                    network: network,
                    language: language,
                    groupBy: groupBy
                )
                
                if Task.isCancelled { return }
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.displayedItems = result.displayed
                        viewModel.recentlyAddedItems = result.recentlyAdded
                        viewModel.groupedItems = result.grouped
                    }
                }
            } catch {
                print("Error filtering items: \(error)")
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
                    .id(viewModel.gridResetID)
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isSearchActive)
                .navigationTitle(isSearchActive ? "Search" : viewModel.navigationTitle(for: viewModel.selectedCategory))
                .navigationDestination(for: MediaItem.self) { item in
                    DetailView(item: item, namespace: posterNamespace) { actorName in
                        viewModel.selectedCategory = "All" // Switch to All to check all titles
                        viewModel.searchText = actorName
                        isSearchActive = false // STAY IN LIBRARY VIEW
                        updateDisplayedItems()
                    }
                }
                .navigationDestination(for: DiscoveryFilter.self) { filter in
                    FilteredLibraryGridView(filter: filter, allItems: allItems, namespace: posterNamespace)
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
        .appBackground(network: viewModel.selectedNetwork) // Apply to the whole NavigationSplitView
        .onAppear {
            NotificationManager.shared.requestPermission()
            updateDisplayedItems()
            performMaintenanceRefresh()
            
            // Phase 3 Deep Optimization: Reset context on sleep
            SleepManager.shared.purgeDataCache = {
                // rollBack discards all unsaved changes and faults all objects back to the disk.
                // This is the most effective way to drop memory usage for SwiftData.
                if modelContext.hasChanges {
                    try? modelContext.save()
                }
                modelContext.rollback()
            }
        }
        .onChange(of: viewModel.searchText) { updateDisplayedItems(delay: 300_000_000) }
        .onChange(of: viewModel.sortOrder) { updateDisplayedItems() }
        .onChange(of: viewModel.selectedGroupBy) { updateDisplayedItems() }
        .onChange(of: allItems) { updateDisplayedItems() }
        .onReceive(NotificationCenter.default.publisher(for: .mediaStateChanged)) { _ in
            updateDisplayedItems()
        }
        .onChange(of: SleepManager.shared.isAsleep) { oldValue, isAsleep in
            if !isAsleep {
                // FORCE A HARD RESET OF VIEW IDENTITY ON WAKE
                viewModel.gridResetID = UUID()
                updateDisplayedItems()
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .top) {
            if isSearchActive {
                SearchView(
                    searchText: $viewModel.searchText,
                    isSearchActive: $isSearchActive,
                    submitTrigger: viewModel.searchSubmitTrigger,
                    initialType: currentMediaType
                ) { item in
                    viewModel.navigationPath.append(item)
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            } else if viewModel.selectedCategory == "Discover" {
                DiscoveryHubView(
                    items: allItems,
                    namespace: posterNamespace,
                    viewModel: viewModel,
                    onFilterSelected: { filter in
                        viewModel.navigationPath.append(filter)
                    }
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            } else if viewModel.selectedCategory == "Upcoming" {
                // Force unique identity for Upcoming to avoid layout morph stutter
                MediaGridView(
                    items: viewModel.displayedItems, 
                    recentlyAdded: viewModel.recentlyAddedItems,
                    groupedItems: viewModel.groupedItems,
                    selectedCategory: viewModel.selectedCategory, 
                    showingUpcomingOnly: true,
                    searchText: viewModel.searchText,
                    groupBy: viewModel.selectedGroupBy,
                    selectedNetwork: viewModel.selectedNetwork,
                    namespace: posterNamespace,
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
                    }
                )
                .id("grid_upcoming")
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            } else {
                MediaGridView(
                    items: viewModel.displayedItems, 
                    recentlyAdded: viewModel.recentlyAddedItems,
                    groupedItems: viewModel.groupedItems,
                    selectedCategory: viewModel.selectedCategory, 
                    showingUpcomingOnly: false,
                    searchText: viewModel.searchText,
                    groupBy: viewModel.selectedGroupBy,
                    selectedNetwork: viewModel.selectedNetwork,
                    namespace: posterNamespace,
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
                    }
                )
                .id("grid_standard")
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
    }

    @ViewBuilder
    private var refreshButton: some View {
        Button(action: performBatchRefresh) {
            if viewModel.isBatchRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Label("Refresh All", systemImage: "arrow.clockwise")
            }
        }
        .disabled(viewModel.isBatchRefreshing)
        .help("Refresh metadata for all items in this view")
    }

    @ViewBuilder
    private var displaySettingsMenu: some View {
        Menu {
            Picker("Sort", selection: $viewModel.sortOrder) {
                Text("Alphabetical").tag(SortOrder.alphabetical)
                Text("Newest Release").tag(SortOrder.newestRelease)
                Text("Recently Added").tag(SortOrder.recentlyAdded)
            }
            
            Picker("Group", selection: $viewModel.selectedGroupBy) {
                Text("None").tag(GroupBy.none)
                Text("By Year").tag(GroupBy.year)
                Text("By Category").tag(GroupBy.category)
            }
        } label: {
            Label("Display", systemImage: "line.3.horizontal.decrease.circle")
        }
    }
    
    @State private var hasRunMaintenance = false
    
    private func performMaintenanceRefresh() {
        guard !hasRunMaintenance else { return }
        hasRunMaintenance = true
        
        // Find TV shows that haven't been updated in 24 hours
        let staleThreshold = Date().addingTimeInterval(-24 * 60 * 60)
        let staleItems = allItems.filter { $0.type == .tvShow && ($0.lastUpdated ?? .distantPast) < staleThreshold }
        
        if staleItems.isEmpty { return }
        
        print("🧹 Maintenance: Refreshing \(staleItems.count) stale TV shows...")
        DataService.shared.refreshMetadata(for: staleItems, modelContext: modelContext)
    }
    
    private var currentMediaType: MediaType? {
        MediaType(rawValue: viewModel.selectedCategory ?? "")
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
                Label("Upcoming", systemImage: "calendar")
                    .tag("Upcoming")

                Label("Now Watching", systemImage: "sparkles")
                    .tag("NowWatching")
                
                Label("In Progress", systemImage: "play.circle")
                    .tag("InProgress")
                
                Label("Watchlist", systemImage: "list.bullet.rectangle")
                    .tag("Watchlist")

                Label("Library", systemImage: "tray.full")
                    .tag("All")
            }
            .padding(.vertical, 4)
            
            Section("Smart Folders") {
                Label("On Hold", systemImage: "pause.circle")
                    .tag("OnHold")
                Label("Dropped", systemImage: "xmark.bin")
                    .tag("Dropped")
                Label("Re-watching", systemImage: "arrow.clockwise.circle")
                    .tag("Rewatching")
            }
            .padding(.vertical, 4)
            
            Section("Explore") {
                Label("Discover", systemImage: "sparkles.tv")
                    .tag("Discover")
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
    guard item.type == .tvShow else { return MediaState.allCases }
    
    if item.hasWatchedAllEpisodes {
        return [.completed]
    }
    
    if item.hasWatchedAnyEpisode {
        return [.active, .completed]
    }
    
    return MediaState.allCases
}

struct MediaGridView: View {
    let items: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let groupedItems: [(String, [MediaThumbnailMetadata])]
    let selectedCategory: String?
    let showingUpcomingOnly: Bool
    let searchText: String
    let groupBy: GroupBy
    let selectedNetwork: String?
    let namespace: Namespace.ID
    let onSelectHero: (MediaThumbnailMetadata) -> Void
    let onNetworkSelected: (String) -> Void
    
    @Environment(\.modelContext) private var modelContext
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]
    
    var isCategoryPage: Bool {
        guard let cat = selectedCategory else { return false }
        return MediaType(rawValue: cat) != nil
    }

    var isMainSection: Bool {
        ["NowWatching", "InProgress", "Watchlist", "All"].contains(selectedCategory)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !searchText.isEmpty && !items.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Search Results")
                            .font(.system(size: 28, weight: .bold))
                            .padding(.horizontal, 30)
                    }
                } else if showingUpcomingOnly && searchText.isEmpty && selectedNetwork == nil {
                    // Hero Section for Upcoming
                    if items.isEmpty {
                        LibraryEmptyStateView(category: selectedCategory)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Featured")
                                .font(.system(size: 28, weight: .bold))
                                .padding(.horizontal, 30)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 25) {
                                    ForEach(items.prefix(5)) { metadata in
                                        MediaThumbnailView(metadata: metadata, mode: .hero, isUpcomingSection: true, namespace: namespace)
                                            .id(metadata.versionHash)
                                            .onTapGesture { onSelectHero(metadata) }
                                    }
                                }
                                .padding(.horizontal, 30)
                                .padding(.bottom, 10)
                            }
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 15) {
                    if let network = selectedNetwork {
                        HStack {
                            Text(network)
                                .font(.system(size: 24, weight: .bold))
                            
                            Button {
                                withAnimation {
                                    onNetworkSelected("") // Logic to clear in parent
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 30)
                    } else if !isCategoryPage && !isMainSection && selectedCategory != "Upcoming" {
                        Text(selectedCategory ?? "Library")
                            .font(.system(size: 24, weight: .bold))
                            .padding(.horizontal, 30)
                    } else if selectedCategory == "Upcoming" {
                        Text("Queue")
                            .font(.system(size: 24, weight: .bold))
                            .padding(.horizontal, 30)
                    }
                    
                    if items.isEmpty {
                        LibraryEmptyStateView(category: selectedCategory)
                    } else {
                        // 1. Recently Added Row
                        if selectedCategory == "All" && searchText.isEmpty && selectedNetwork == nil {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("Recently Added")
                                    .font(.system(size: 24, weight: .bold))
                                    .padding(.horizontal, 30)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(recentlyAdded) { metadata in
                                            if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                                NavigationLink(value: item) {
                                                    MediaThumbnailView(metadata: metadata, mode: .grid)
                                                        .id(metadata.versionHash)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 30)
                                }
                            }
                            .padding(.bottom, 20)
                            
                            Divider().padding(.horizontal, 30).padding(.bottom, 20)
                        }

                        if groupBy == .none {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                let displayItems = showingUpcomingOnly ? Array(items.dropFirst(min(items.count, 5))) : items
                                
                                ForEach(displayItems) { metadata in
                                    if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                        NavigationLink(value: item) {
                                            MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: !isCategoryPage, isUpcomingSection: showingUpcomingOnly, namespace: namespace)
                                                .id(metadata.versionHash)
                                        }
                                        .buttonStyle(.plain)
                                        .draggable(item.id)
                                    }
                                }
                            }
                            .drawingGroup()
                            .padding(.horizontal, 30)
                            .padding(.bottom, 40)
                        } else {
                            // Pre-calculated Grouped View
                            VStack(alignment: .leading, spacing: 40) {
                                ForEach(groupedItems, id: \.0) { (key, groupMetadatas) in
                                    VStack(alignment: .leading, spacing: 15) {
                                        Text(key)
                                            .font(.title2.bold())
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 30)
                                        
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                            ForEach(groupMetadatas) { metadata in
                                                if let item = modelContext.model(for: metadata.id) as? MediaItem {
                                                    NavigationLink(value: item) {
                                                        MediaThumbnailView(metadata: metadata, mode: .grid, showTypeBadge: groupBy != .category, isUpcomingSection: showingUpcomingOnly, namespace: namespace)
                                                            .id(metadata.versionHash)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                        .drawingGroup()
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
        }
    }
}

struct FilteredLibraryGridView: View {
    let filter: DiscoveryFilter
    let allItems: [MediaItem]
    let namespace: Namespace.ID
    @AppStorage("app_accent") private var appAccent: AppAccent = .indigo

    var body: some View {
        let filteredItems = allItems.filter { item in
            switch filter.type {
            case .genre:
                let genres = !item.cachedGenres.isEmpty ? item.cachedGenres : (item.movieDetails?.genres ?? item.tvShowDetails?.genres ?? [])
                return genres.contains(filter.name)
            case .studio:
                return item.cachedNetwork == filter.name
            case .language:
                let language = item.cachedLanguage ?? item.movieDetails?.originalLanguage ?? item.tvShowDetails?.originalLanguage
                return language == filter.name
            }
        }.sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let columns = [GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(filteredItems) { item in
                        NavigationLink(value: item) {
                            MediaThumbnailView(item: item, mode: .grid, namespace: namespace)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .drawingGroup()
                .padding(.horizontal, 30)
            }
            .padding(.vertical, 20)
        }
        .navigationTitle(displayTitle)
        .appBackground(
            network: filter.type == .studio ? filter.name : nil,
            tint: filter.type != .studio ? appAccent.color : nil
        )
    }

    private var displayTitle: String {
        if filter.type == .language {
            return Locale.current.localizedString(forLanguageCode: filter.name) ?? filter.name.uppercased()
        }
        return filter.name
    }
}
