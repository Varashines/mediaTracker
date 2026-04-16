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
        if category == "All" { return "Library" }
        return category ?? "Library"
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MediaItem.title) private var allItems: [MediaItem]
    @State private var viewModel = MediaViewModel()
    @State private var isSearchActive = false
    @State private var selectedHeroItem: MediaItem? = nil
    @State private var displayedItems: [MediaItem] = []
    
    private func updateDisplayedItems() {
        let category = viewModel.selectedCategory
        let searchText = viewModel.searchText
        let items = allItems
        
        Task { @MainActor in
            let baseItems: [MediaItem]
            
            if category == "Upcoming" || category == nil {
                baseItems = items.filter { $0.isUpcoming }
                    .sorted { item1, item2 in
                        guard let date1 = item1.nextAiringDate else { return false }
                        guard let date2 = item2.nextAiringDate else { return true }
                        return date1 < date2
                    }
            } else if category == "InProgress" {
                baseItems = items.filter { $0.isActive && !$0.isUpcoming }
            } else if category == "Waitlist" {
                baseItems = items.filter { $0.state == .wishlist && !$0.isUpcoming }
            } else if category == "All" {
                baseItems = items
            } else {
                baseItems = items.filter { $0.type?.rawValue == category }
            }
            
            let finalResults: [MediaItem]
            if searchText.isEmpty {
                finalResults = baseItems
            } else {
                finalResults = baseItems.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
            }
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                self.displayedItems = finalResults
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
                
                Section("Categories") {
                    ForEach(MediaType.allCases, id: \.self) { type in
                        Label(type.pluralName, systemImage: icon(for: type))
                            .tag(type.rawValue)
                            .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Library")
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
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
                            items: displayedItems, 
                            selectedCategory: viewModel.selectedCategory, 
                            showingUpcomingOnly: viewModel.selectedCategory == "Upcoming",
                            searchText: viewModel.searchText,
                            onSelectHero: { item in
                                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                    viewModel.navigationPath.append(item)
                                }
                            }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isSearchActive)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: viewModel.selectedCategory)
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
        .onAppear {
            NotificationManager.shared.requestPermission()
            updateDisplayedItems()
        }
        .onChange(of: viewModel.selectedCategory) { updateDisplayedItems() }
        .onChange(of: viewModel.searchText) { updateDisplayedItems() }
        .onChange(of: allItems) { updateDisplayedItems() }
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
    let onSelectHero: (MediaItem) -> Void
    
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
        return ["InProgress", "Waitlist", "All"].contains(cat)
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
                                    MediaHeroCard(item: item)
                                        .onTapGesture { onSelectHero(item) }
                                }
                            }
                            .padding(.horizontal, 30)
                            .padding(.bottom, 10)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 15) {
                    if !isCategoryPage && !isMainSection && selectedCategory != "Upcoming" {
                        Text(selectedCategory ?? "Library")
                            .font(.system(size: 24, weight: .bold))
                            .padding(.horizontal, 30)
                    } else if selectedCategory == "Upcoming" {
                        Text("Queue")
                            .font(.system(size: 24, weight: .bold))
                            .padding(.horizontal, 30)
                    }
                    
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        let displayItems = (showingUpcomingOnly && items.count > 5) ? Array(items.dropFirst(5)) : items
                        
                        ForEach(displayItems) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item, showTypeBadge: !isCategoryPage)
                            }
                            .buttonStyle(.plain)
                            .draggable(item.id)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.bottom, 40)
                }
            }
            .padding(.vertical, 20)
        }
        .dropDestination(for: String.self) { items, location in
            return false // Base scrollview doesn't handle drops directly for state changes
        }
    }
}

struct MediaHeroCard: View {
    let item: MediaItem
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .top) {
                // 1. Poster Layer
                if let urlString = item.posterURL, let url = URL(string: urlString) {
                    CachedImage(url: url, targetSize: CGSize(width: 400, height: 600)) { _ in } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.1))
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 200, height: 300)
                    .clipped()
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                        .frame(width: 200, height: 300)
                }
                
                // 2. Glass Pills (Top Corners)
                topPills
                
                // 3. Info Pill (Bottom Center) - Only for Upcoming
                if item.isUpcoming {
                    VStack {
                        Spacer()
                        infoRow
                            .padding(8)
                    }
                }
            }
            .frame(width: 200, height: 300)
            .cornerRadius(16)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            
            // 4. Info Section (Below)
            Text(item.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    @ViewBuilder
    private var topPills: some View {
        HStack(alignment: .top) {
            categoryPill
            Spacer()
            statusPill
        }
        .padding(8)
    }
    
    @ViewBuilder
    private var categoryPill: some View {
        Group {
            switch item.type {
            case .movie: Image(systemName: "film")
            case .tvShow: Image(systemName: "tv")
            case .book: Image(systemName: "book")
            case .none: EmptyView()
            }
        }
        .font(.system(size: 10, weight: .bold))
        .liquidGlassPill(accentColor: .accentColor, isSolid: false)
    }
    
    @ViewBuilder
    private var statusPill: some View {
        Group {
            if item.isUpcoming {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(accentColor: .green, isSolid: true)
            } else if item.isActive {
                HStack(spacing: 2) {
                    Image(systemName: "play.circle.fill")
                    Text(item.watchProgressLabel ?? "")
                }
                .foregroundStyle(.white)
                .liquidGlassPill(accentColor: .indigo, isSolid: true)
            } else if item.state == .wishlist && !item.isUpcoming {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(accentColor: .orange, isSolid: true)
            }
        }
        .font(.system(size: 10, weight: .bold))
    }
    
    @ViewBuilder
    private var infoRow: some View {
        Group {
            if item.isUpcoming {
                Text(item.nextAiringLabel ?? "")
                    .foregroundStyle(item.isRecentlyReleased ? .green : .primary)
                    .font(.system(size: 10, weight: .bold))
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .wishlist {
                Text("Waitlist")
                    .foregroundStyle(.orange)
                    .font(.system(size: 10, weight: .bold))
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .completed {
                Text("Completed")
                    .foregroundStyle(.green)
                    .font(.system(size: 10, weight: .bold))
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    Text(item.watchProgressLabel ?? "In Progress")
                }
                .foregroundStyle(.indigo)
                .font(.system(size: 10, weight: .bold))
                .liquidGlassPill(accentColor: .primary, isSolid: false)
            }
        }
    }
}

struct MediaCard: View {
    @Environment(\.modelContext) private var modelContext
    let item: MediaItem
    let showTypeBadge: Bool
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .top) {
                // 1. Poster Layer
                Group {
                    if let urlString = item.posterURL, let url = URL(string: urlString) {
                        CachedImage(url: url, targetSize: CGSize(width: 160, height: 240)) { _ in
                        } placeholder: {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.1))
                                .overlay { ProgressView().controlSize(.small) }
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 240)
                        .clipped()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 160, height: 240)
                    }
                }
                
                // 2. Glass Pills (Top Corners)
                topPills
                
                // 3. Info Pill (Bottom Center) - Only for Upcoming
                if item.isUpcoming {
                    VStack {
                        Spacer()
                        infoRow
                            .padding(6)
                    }
                }
            }
            .frame(width: 160, height: 240)
            .cornerRadius(12)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            
            // 4. Info Section (Below Poster)
            Text(item.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(height: 34, alignment: .topLeading)
                .padding(.horizontal, 2)
        }
        .frame(width: 160)
        .contentShape(Rectangle())
        .drawingGroup()
        .onHover { hovering in
            isHovered = hovering
        }
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
    private var topPills: some View {
        HStack(alignment: .top) {
            if showTypeBadge {
                categoryPill
            }
            Spacer()
            statusPill
        }
        .padding(6)
    }
    
    @ViewBuilder
    private var categoryPill: some View {
        Group {
            switch item.type {
            case .movie: Image(systemName: "film")
            case .tvShow: Image(systemName: "tv")
            case .book: Image(systemName: "book")
            case .none: EmptyView()
            }
        }
        .font(.system(size: 9, weight: .bold)) // Standardized height
        .liquidGlassPill(accentColor: .accentColor, isSolid: false)
    }
    
    @ViewBuilder
    private var statusPill: some View {
        Group {
            if item.isUpcoming {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(accentColor: .green, isSolid: true)
            } else if item.isActive {
                HStack(spacing: 2) {
                    Image(systemName: "play.circle.fill")
                    Text(item.watchProgressLabel ?? "")
                }
                .foregroundStyle(.white)
                .liquidGlassPill(accentColor: .indigo, isSolid: true) // Changed to Indigo
            } else if item.state == .wishlist && !item.isUpcoming {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.white)
                    .liquidGlassPill(accentColor: .orange, isSolid: true)
            }
        }
        .font(.system(size: 9, weight: .bold)) // Standardized height
    }
    
    @ViewBuilder
    private var infoRow: some View {
        Group {
            if item.isUpcoming {
                Text(item.nextAiringLabel ?? "")
                    .foregroundStyle(item.isRecentlyReleased ? .green : .primary)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .wishlist {
                Text("Waitlist") // Icon removed
                    .foregroundStyle(.orange)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else if item.state == .completed {
                Text("Completed")
                    .foregroundStyle(.green)
                    .liquidGlassPill(accentColor: .primary, isSolid: false)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                    Text(item.watchProgressLabel ?? "In Progress")
                }
                .foregroundStyle(.indigo) // Changed to Indigo
                .liquidGlassPill(accentColor: .primary, isSolid: false)
            }
        }
        .font(.system(size: 9, weight: .bold)) // Standardized height
    }
}
