import SwiftUI
import SwiftData
import CoreSpotlight

@Observable
class MediaViewModel {
    var selectedCategory: String? = "Upcoming"
    var searchText: String = ""
    var navigationPath = NavigationPath()
    var searchSubmitTrigger: Int = 0
    
    func navigationTitle(for category: String?) -> String {
        if let cat = category, let type = MediaType(rawValue: cat) {
            return type.pluralName
        }
        if category == "InProgress" { return "In Progress" }
        return category ?? "Library"
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.title) private var allItems: [MediaItem]
    @State private var viewModel = MediaViewModel()
    @State private var isSearchActive = false
    
    var filteredItems: [MediaItem] {
        let baseItems: [MediaItem]
        let category = viewModel.selectedCategory
        
        if category == "Upcoming" || category == nil {
            baseItems = allItems.filter { $0.isUpcoming }
                .sorted { item1, item2 in
                    guard let date1 = item1.nextAiringDate else { return false }
                    guard let date2 = item2.nextAiringDate else { return true }
                    return date1 < date2
                }
        } else if category == "InProgress" {
            baseItems = allItems.filter { $0.isActive && !$0.isUpcoming }
        } else if category == "Waitlist" {
            baseItems = allItems.filter { $0.state == .wishlist && !$0.isUpcoming }
        } else if category == "All" {
            baseItems = allItems
        } else {
            baseItems = allItems.filter { $0.type?.rawValue == category }
        }
        
        if viewModel.searchText.isEmpty {
            return baseItems
        } else {
            return baseItems.filter { $0.title.localizedCaseInsensitiveContains(viewModel.searchText) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $viewModel.selectedCategory) {
                Label("Upcoming", systemImage: "calendar")
                    .tag("Upcoming")
                
                Label("In Progress", systemImage: "play.circle")
                    .tag("InProgress")
                
                Label("Waitlist", systemImage: "clock")
                    .tag("Waitlist")

                Label("Library", systemImage: "tray.full")
                    .tag("All")
                
                Section("Categories") {
                    ForEach(MediaType.allCases, id: \.self) { type in
                        Label(type.pluralName, systemImage: icon(for: type))
                            .tag(type.rawValue)
                    }
                }
            }
            .navigationTitle("Library")
        } detail: {
            NavigationStack(path: $viewModel.navigationPath) {
                Group {
                    if isSearchActive {
                        SearchView(
                            searchText: $viewModel.searchText,
                            isSearchActive: $isSearchActive,
                            submitTrigger: viewModel.searchSubmitTrigger,
                            initialType: currentMediaType
                        ) { item in
                            viewModel.navigationPath.append(item)
                        }
                        .transition(.opacity)
                    } else {
                        MediaGridView(
                            items: filteredItems, 
                            selectedCategory: viewModel.selectedCategory, 
                            showingUpcomingOnly: viewModel.selectedCategory == "Upcoming",
                            searchText: viewModel.searchText
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.default, value: isSearchActive)
                .navigationTitle(isSearchActive ? "Search" : viewModel.navigationTitle(for: viewModel.selectedCategory))
                .navigationDestination(for: MediaItem.self) { item in
                    DetailView(item: item)
                }
                .searchable(text: $viewModel.searchText, isPresented: $isSearchActive, prompt: "Search movies, shows, books...")
                .onSubmit(of: .search) {
                    viewModel.searchSubmitTrigger += 1
                }
            }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            if let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                if let item = allItems.first(where: { $0.id == identifier }) {
                    viewModel.navigationPath = NavigationPath([item])
                }
            }
        }
    }
    
    private var currentMediaType: MediaType? {
        MediaType(rawValue: viewModel.selectedCategory ?? "")
    }
    
    private func icon(for type: MediaType) -> String {
        switch type {
        case .movie: return "film"
        case .tvShow: return "tv"
        case .book: return "book"
        }
    }
}

struct MediaGridView: View {
    let items: [MediaItem]
    let selectedCategory: String?
    let showingUpcomingOnly: Bool
    let searchText: String
    
    @Environment(\.modelContext) private var modelContext
    
    let columns = [
        GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if !searchText.isEmpty {
                    // Search Mode: Simple Grid of filtered items
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if showingUpcomingOnly {
                    stateSection(title: "Upcoming & Recent", items: items)
                } else if itemsAreArchive {
                    // Simple grid for 'Library' only
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    // Filter items by type if we are in a category view
                    let typeFilter = MediaType(rawValue: selectedCategory ?? "")
                    let contextItems = typeFilter != nil ? items.filter { $0.type == typeFilter } : items

                    // 1. Upcoming
                    let upcoming = contextItems.filter { $0.isUpcoming }
                        .sorted { item1, item2 in
                            guard let date1 = item1.nextAiringDate else { return false }
                            guard let date2 = item2.nextAiringDate else { return true }
                            return date1 < date2
                        }
                    if !upcoming.isEmpty {
                        stateSection(title: "Upcoming", items: upcoming)
                    }
                    
                    // 2. In Progress
                    let active = contextItems.filter { $0.isActive && !$0.isUpcoming }
                    if !active.isEmpty {
                        stateSection(title: "In Progress", items: active)
                    }
                    
                    // 3. Waitlist
                    let waitlist = contextItems.filter { !$0.isUpcoming && !$0.isActive && $0.state != .completed }
                    if !waitlist.isEmpty {
                        stateSection(title: "Waitlist", items: waitlist)
                    }
                    
                    // 4. Completed
                    let completed = contextItems.filter { !$0.isUpcoming && $0.state == .completed }
                    if !completed.isEmpty {
                        stateSection(title: "Completed", items: completed)
                    }
                }
            }
            .padding()
        }
    }
    
    private var itemsAreArchive: Bool {
        selectedCategory == "All"
    }
    
    @ViewBuilder
    private func stateSection(title: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.title2.bold())
                .padding(.bottom, 10)
            
            ZStack {
                if items.isEmpty {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.05))
                        .frame(height: 120)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "plus.square.dashed")
                                    .font(.title)
                                Text("No items in \(title)")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                        }
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item)
                                    .onDrag {
                                        NSItemProvider(object: item.id as NSString)
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: items)
            .padding(.vertical, 8)
            .onDrop(of: [.text], isTargeted: nil) { providers in
                if let targetState = MediaState.allCases.first(where: { $0.displayName == title }) {
                    return handleDrop(providers: providers, targetState: targetState)
                }
                return false
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider], targetState: MediaState) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadObject(ofClass: NSString.self) { id, error in
            guard let id = id as? String else { return }
            
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if let item = items.first(where: { $0.id == id }) {
                        item.state = targetState
                    }
                }
            }
        }
        return true
    }
}

struct MediaCard: View {
    @Environment(\.modelContext) private var modelContext
    let item: MediaItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottom) {
                // Poster with fixed size
                Group {
                    if let urlString = item.posterURL, let url = URL(string: urlString) {
                        CachedImage(url: url, targetSize: CGSize(width: 480, height: 720)) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .overlay { ProgressView().controlSize(.small) }
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 240)
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 160, height: 240)
                .clipped()
                .cornerRadius(12)
                .shadow(radius: 2)
                
                // Status Badge (Top Right)
                VStack {
                    HStack {
                        Spacer()
                        Text(item.state?.displayName ?? "")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(8)
                    }
                    Spacer()
                }
                
                // Overlay (Bottom)
                if item.isUpcoming {
                    upcomingBadge
                } else {
                    watchStatusOverlay
                }
            }
            .frame(width: 160, height: 240)
            
            // Text Content - Fixed height to ensure posters align perfectly
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 40, alignment: .topLeading)
                
                Text(item.type?.rawValue ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 160)
        .contentShape(Rectangle())
        .contextMenu {
            Section("Status") {
                ForEach(MediaState.allCases, id: \.self) { state in
                    Button(state.displayName) {
                        item.state = state
                    }
                }
            }
            Divider()
            Button(role: .destructive) {
                NotificationManager.shared.cancelNotification(for: item)
                SpotlightManager.shared.removeItem(item)
                modelContext.delete(item)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder
    private var watchStatusOverlay: some View {
        Group {
            if item.state == .completed {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Completed")
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.green.opacity(0.8))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(8)
            } else if item.isActive {
                HStack(spacing: 4) {
                    Image(systemName: "play.circle.fill")
                    Text(item.watchProgressLabel ?? "In Progress")
                }
                .font(.system(size: 10, weight: .bold))
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(8)
            }
        }
    }
    
    @ViewBuilder
    private var upcomingBadge: some View {
        if let label = item.nextAiringLabel {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background(item.isRecentlyReleased ? AnyShapeStyle(Color.green.opacity(0.8)) : AnyShapeStyle(Material.ultraThinMaterial))
                .foregroundStyle(item.isRecentlyReleased ? .white : .primary)
        }
    }
}
