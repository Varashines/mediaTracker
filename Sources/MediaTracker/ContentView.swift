import SwiftUI
import SwiftData
import CoreSpotlight

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

    // Processed Data (Main Actor Cache)
    var displayedItems: [MediaItem] = []
    var recentlyAddedItems: [MediaItem] = []
    var groupedItems: [(String, [MediaItem])] = []

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
                
                // Fault models back onto the MainActor
                let displayed = result.displayedIDs.compactMap { self.modelContext.model(for: $0) as? MediaItem }
                let recentlyAdded = result.recentlyAddedIDs.compactMap { self.modelContext.model(for: $0) as? MediaItem }
                let grouped = result.groupedIDs.map { (key, ids) in
                    (key, ids.compactMap { self.modelContext.model(for: $0) as? MediaItem })
                }
                
                await MainActor.run {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        viewModel.displayedItems = displayed
                        viewModel.recentlyAddedItems = recentlyAdded
                        viewModel.groupedItems = grouped
                    }
                }
            } catch {
                print("Error filtering items: \(error)")
            }
        }
    }
    
    private func performBatchRefresh() {
        let itemsToRefresh = viewModel.displayedItems
        viewModel.isBatchRefreshing = true
        
        DataService.shared.refreshMetadata(for: itemsToRefresh, modelContext: modelContext)
        
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                viewModel.isBatchRefreshing = false
                updateDisplayedItems()
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedCategory) {
                Group {
                    Label("Upcoming", systemImage: "calendar")
                        .tag("Upcoming")
                    
                    Label("In Progress", systemImage: "play.circle")
                        .tag("InProgress")
                    
                    Label("Waitlist", systemImage: "clock")
                        .tag("Waitlist")

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
                        Label(type.pluralName, systemImage: icon(for: type))
                            .tag(type.rawValue)
                            .padding(.vertical, 4)
                    }
                }
            }
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
                            onSelectHero: { item in
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    viewModel.navigationPath.append(item)
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
                            onSelectHero: { item in
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    viewModel.navigationPath.append(item)
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
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isSearchActive)
                .navigationTitle(isSearchActive ? "Search" : viewModel.navigationTitle(for: viewModel.selectedCategory))
                .navigationDestination(for: MediaItem.self) { item in
                    DetailView(item: item, namespace: posterNamespace) { actorName in
                        viewModel.selectedCategory = "All" // Switch to All to check all titles
                        viewModel.searchText = actorName
                        isSearchActive = false // STAY IN LIBRARY VIEW
                        viewModel.navigationPath = NavigationPath() // Clear path to go back to grid
                    }
                }
                .navigationDestination(for: DiscoveryFilter.self) { filter in
                    FilteredLibraryGridView(filter: filter, allItems: allItems, namespace: posterNamespace)
                }
                .searchable(text: $viewModel.searchText, isPresented: $isSearchActive, prompt: "Search movies, shows...")
                .onSubmit(of: .search) {
                    viewModel.searchSubmitTrigger += 1
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if !isSearchActive && isSortable {
                            Menu {
                                Picker("Sort By", selection: $viewModel.sortOrder) {
                                    ForEach(SortOrder.allCases) { order in
                                        Label(order.rawValue, systemImage: order.icon)
                                            .tag(order)
                                    }
                                }
                                
                                Picker("Group By", selection: $viewModel.selectedGroupBy) {
                                    ForEach(GroupBy.allCases) { group in
                                        Label(group.rawValue, systemImage: group.icon)
                                            .tag(group)
                                    }
                                }
                            } label: {
                                Label("Display Settings", systemImage: "line.3.horizontal.decrease.circle")
                            }
                        }
                    }
                    
                    ToolbarItem(placement: .primaryAction) {
                        if !isSearchActive && isSortable {
                            Button {
                                performBatchRefresh()
                            } label: {
                                if viewModel.isBatchRefreshing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Label("Refresh All", systemImage: "arrow.clockwise")
                                }
                            }
                            .disabled(viewModel.isBatchRefreshing)
                            .help("Refresh metadata for all items in this view")
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
        }
        .appBackground(network: viewModel.selectedNetwork) // Apply to the whole NavigationSplitView
        .onAppear {
            NotificationManager.shared.requestPermission()
            updateDisplayedItems()
            performMaintenanceRefresh()
        }
        .onChange(of: viewModel.selectedCategory) {
            viewModel.selectedNetwork = nil // RESET NETWORK FILTER ON CATEGORY CHANGE
            updateDisplayedItems()
        }
        .onChange(of: viewModel.searchText) { updateDisplayedItems(delay: 300_000_000) }
        .onChange(of: viewModel.sortOrder) { updateDisplayedItems() }
        .onChange(of: viewModel.selectedGroupBy) { updateDisplayedItems() }
        .onChange(of: allItems) { updateDisplayedItems() }
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            if let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                if let item = allItems.first(where: { $0.id == identifier }) {
                    viewModel.navigationPath = NavigationPath([item])
                }
            }
        }
    }
    
    @State private var hasRunMaintenance = false
    
    private func performMaintenanceRefresh() {
        guard !hasRunMaintenance else { return }
        hasRunMaintenance = true
        
        let staleItems = allItems.filter { $0.requiresMaintenanceRefresh }
        guard !staleItems.isEmpty else { return }
        
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
    let items: [MediaItem]
    let recentlyAdded: [MediaItem]
    let groupedItems: [(String, [MediaItem])]
    let selectedCategory: String?
    let showingUpcomingOnly: Bool
    let searchText: String
    let groupBy: GroupBy
    let selectedNetwork: String?
    let namespace: Namespace.ID
    let onSelectHero: (MediaItem) -> Void
    let onNetworkSelected: (String) -> Void
    
    @Environment(\.modelContext) private var modelContext
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]
    
    private var isCategoryPage: Bool {
        guard let cat = selectedCategory else { return false }
        return MediaType(rawValue: cat) != nil
    }
    
    private var isMainSection: Bool {
        guard let cat = selectedCategory else { return false }
        return ["InProgress", "Waitlist", "All", "OnHold", "Dropped", "Rewatching"].contains(cat)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if showingUpcomingOnly && !items.isEmpty {
                    VStack(alignment: .leading, spacing: 15) {
                        Text("Featured")
                            .font(.system(size: 28, weight: .bold))
                            .padding(.horizontal, 30)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 20) {
                                ForEach(items.prefix(5)) { item in
                                    MediaThumbnailView(item: item, mode: .hero, namespace: namespace)
                                        .onTapGesture { onSelectHero(item) }
                                }
                            }
                            .padding(.horizontal, 30)
                            .padding(.bottom, 10)
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
                                        ForEach(recentlyAdded) { item in
                                            NavigationLink(value: item) {
                                                MediaThumbnailView(item: item, mode: .grid)
                                            }
                                            .buttonStyle(.plain)
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
                                
                                ForEach(displayItems) { item in
                                    NavigationLink(value: item) {
                                        MediaThumbnailView(item: item, mode: .grid, showTypeBadge: !isCategoryPage, namespace: namespace)
                                    }
                                    .buttonStyle(.plain)
                                    .draggable(item.id)
                                }
                            }
                            .drawingGroup()
                            .padding(.horizontal, 30)
                            .padding(.bottom, 40)
                        } else {
                            // Pre-calculated Grouped View
                            VStack(alignment: .leading, spacing: 40) {
                                ForEach(groupedItems, id: \.0) { (key, groupItems) in
                                    VStack(alignment: .leading, spacing: 15) {
                                        Text(key)
                                            .font(.title2.bold())
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 30)
                                        
                                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                            ForEach(groupItems) { item in
                                                NavigationLink(value: item) {
                                                    MediaThumbnailView(item: item, mode: .grid, showTypeBadge: groupBy != .category, namespace: namespace)
                                                }
                                                .buttonStyle(.plain)
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
                return item.cachedGenres.contains(filter.name)
            case .studio:
                return item.cachedNetwork == filter.name
            case .language:
                return item.cachedLanguage == filter.name
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

