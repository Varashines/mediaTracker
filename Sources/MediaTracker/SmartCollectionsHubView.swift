import SwiftUI
import SwiftData

private actor HubCountsCache {
    static let shared = HubCountsCache()
    private var counts: [NavigationCategory: Int]?
    private var customCounts: [UUID: Int]?
    private var savedAt: Date?

    func load() -> ([NavigationCategory: Int], [UUID: Int])? {
        guard let savedAt, savedAt > Date().addingTimeInterval(-300) else {
            counts = nil; customCounts = nil; return nil
        }
        guard let counts, let customCounts else { return nil }
        return (counts, customCounts)
    }

    func save(counts: [NavigationCategory: Int], customCounts: [UUID: Int]) {
        self.counts = counts
        self.customCounts = customCounts
        savedAt = Date()
    }
}

struct SmartCollectionsHubView: View {
    let namespace: Namespace.ID
    @Binding var selection: SidebarItem?
    
    @Environment(\.modelContext) private var modelContext

    @AppStorage("pinned_system_categories") private var pinnedSystemCategories: String = "Release Radar"
    
    @State private var counts: [NavigationCategory: Int] = [:]
    @State private var customSmartCounts: [UUID: Int] = [:]
    @State private var countsLoaded = false
    @State private var showingCreateSheet = false
    @State private var initialIsSmart = true
    @State private var customSmartCollections: [MediaCollection] = []
    @State private var manualCollections: [MediaCollection] = []
    
    private let smartCategories: [NavigationCategory] = [
        .releaseRadar, .smartUpcoming, .catchUp, .loved, .binge, .quickBites
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 35) {
                // 1. SYSTEM SMART COLLECTIONS
                sectionHeaderMini("System Intelligence")
                    .padding(.horizontal, 40)
                    .padding(.top, 40)

                Grid(alignment: .leading, horizontalSpacing: 25, verticalSpacing: 25) {
                    let pinnedList = pinnedSystemCategories.split(separator: ",").map(String.init)
                    
                    GridRow {
                        // Release Radar (spans 2)
                        let releaseRadar = NavigationCategory.releaseRadar
                        SmartCollectionCard(
                            title: releaseRadar.title,
                            icon: releaseRadar.icon,
                            description: description(for: releaseRadar),
                            count: countsLoaded ? counts[releaseRadar] : nil,
                            accentColor: Color.accentColor,
                            isPinned: pinnedList.contains(releaseRadar.rawValue),
                            onPinToggle: { togglePinned(releaseRadar) }
                        ) {
                            selection = .category(releaseRadar)
                        }
                        .gridCellColumns(2)
                        
                        // Smart Upcoming (spans 1)
                        let smartUpcoming = NavigationCategory.smartUpcoming
                        SmartCollectionCard(
                            title: smartUpcoming.title,
                            icon: smartUpcoming.icon,
                            description: description(for: smartUpcoming),
                            count: countsLoaded ? counts[smartUpcoming] : nil,
                            accentColor: Color.accentColor,
                            isPinned: pinnedList.contains(smartUpcoming.rawValue),
                            onPinToggle: { togglePinned(smartUpcoming) }
                        ) {
                            selection = .category(smartUpcoming)
                        }
                    }
                    
                    GridRow {
                        // Catch Up (spans 2)
                        let catchUp = NavigationCategory.catchUp
                        SmartCollectionCard(
                            title: catchUp.title,
                            icon: catchUp.icon,
                            description: description(for: catchUp),
                            count: countsLoaded ? counts[catchUp] : nil,
                            accentColor: Color.accentColor,
                            isPinned: pinnedList.contains(catchUp.rawValue),
                            onPinToggle: { togglePinned(catchUp) }
                        ) {
                            selection = .category(catchUp)
                        }
                        .gridCellColumns(2)
                        
                        // Loved (spans 1)
                        let loved = NavigationCategory.loved
                        SmartCollectionCard(
                            title: loved.title,
                            icon: loved.icon,
                            description: description(for: loved),
                            count: countsLoaded ? counts[loved] : nil,
                            accentColor: Color.accentColor,
                            isPinned: pinnedList.contains(loved.rawValue),
                            onPinToggle: { togglePinned(loved) }
                        ) {
                            selection = .category(loved)
                        }
                    }
                    
                    GridRow {
                        // Binge (spans 1)
                        let binge = NavigationCategory.binge
                        SmartCollectionCard(
                            title: binge.title,
                            icon: binge.icon,
                            description: description(for: binge),
                            count: countsLoaded ? counts[binge] : nil,
                            accentColor: Color.accentColor,
                            isPinned: pinnedList.contains(binge.rawValue),
                            onPinToggle: { togglePinned(binge) }
                        ) {
                            selection = .category(binge)
                        }
                        
                        // Quick Bites (spans 1)
                        let quickBites = NavigationCategory.quickBites
                        SmartCollectionCard(
                            title: quickBites.title,
                            icon: quickBites.icon,
                            description: description(for: quickBites),
                            count: countsLoaded ? counts[quickBites] : nil,
                            accentColor: Color.accentColor,
                            isPinned: pinnedList.contains(quickBites.rawValue),
                            onPinToggle: { togglePinned(quickBites) }
                        ) {
                            selection = .category(quickBites)
                        }
                        
                        // Empty cell to balance the GridRow columns
                        Color.clear
                            .gridCellUnsizedAxes([.horizontal, .vertical])
                    }
                }
                .padding(.horizontal, 40)
                
                // 2. CUSTOM SMART PLAYLISTS
                HStack {
                    sectionHeaderMini("Smart Playlists")
                    Spacer()
                    Button {
                        initialIsSmart = true
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.purple.gradient)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 25)], spacing: 25) {
                    if customSmartCollections.isEmpty {
                        emptyStatePlaceholder(title: "No Smart Playlists", subtitle: "Automate your library organization.", color: .purple) {
                            initialIsSmart = true
                            showingCreateSheet = true
                        }
                    } else {
                        ForEach(customSmartCollections) { collection in
                            SmartCollectionCard(
                                collection: collection,
                                title: collection.name,
                                icon: collection.systemImage,
                                description: "Dynamic playlist based on smart rules.",
                                 count: countsLoaded ? customSmartCounts[collection.id] : nil,
                                accentColor: .purple
                            ) {
                                selection = .collection(collection.id, name: collection.name, icon: collection.systemImage)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)

                // 3. MANUAL COLLECTIONS
                HStack {
                    sectionHeaderMini("Manual Collections")
                    Spacer()
                    Button {
                        initialIsSmart = false
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue.gradient)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 25)], spacing: 25) {
                    if manualCollections.isEmpty {
                        emptyStatePlaceholder(title: "No Manual Collections", subtitle: "Curate your own media sets.", color: .blue) {
                            initialIsSmart = false
                            showingCreateSheet = true
                        }
                    } else {
                        ForEach(manualCollections) { collection in
                            SmartCollectionCard(
                                collection: collection,
                                title: collection.name,
                                icon: collection.systemImage,
                                description: "Hand-picked items for custom viewing.",
                                count: collection.items.count,
                                accentColor: .blue
                            ) {
                                selection = .collection(collection.id, name: collection.name, icon: collection.systemImage)
                            }
                        }
                    }
                }
                .padding(.horizontal, 40)
                
                Spacer(minLength: 50)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showingCreateSheet) {
            CreateCollectionSheet(initialIsSmart: initialIsSmart)
        }
        .task {
            await fetchCollections()
            if let cached = await HubCountsCache.shared.load() {
                self.counts = cached.0
                self.customSmartCounts = cached.1
                self.countsLoaded = true
            } else {
                await fetchCounts()
            }
        }
        .onChange(of: MediaStateService.shared.needsFullRefreshCount) { _, _ in
            let itemID = MediaStateService.shared.lastChangedItemID
            if itemID == nil {
                Task { await fetchCollections() }
            }
        }
    }
    
    private func sectionHeaderMini(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .kerning(1.2)
    }

    private func emptyStatePlaceholder(title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(color.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5]))
            }
        }
        .buttonStyle(.plain)
    }

    private func description(for category: NavigationCategory) -> String {
        switch category {
        case .releaseRadar: return "Recently released episodes and movies from your library."
        case .smartUpcoming: return "Highly anticipated upcoming premieres and release dates."
        case .catchUp: return "Shows with backlogs and new episodes airing this week."
        case .loved: return "Your absolute favorites, marked with a heart."
        case .binge: return "Shows with multiple unwatched episodes available."
        case .quickBites: return "Short media under 90 minutes for quick viewing."
        case .stalled: return "Active titles with no progress in the last 3 months."
        case .archive: return "Completed or dropped items you've archived."
        default: return ""
        }
    }

    private func fetchCollections() async {
        let smart = try? modelContext.fetch(
            FetchDescriptor<MediaCollection>(
                predicate: #Predicate { $0.smartRulesData != nil },
                sortBy: [SortDescriptor(\.name)]
            )
        )
        let manual = try? modelContext.fetch(
            FetchDescriptor<MediaCollection>(
                predicate: #Predicate { $0.smartRulesData == nil },
                sortBy: [SortDescriptor(\.name)]
            )
        )
        if let smart, let manual {
            self.customSmartCollections = smart
            self.manualCollections = manual
        }
    }

    private func fetchCounts() async {
        let actor = MediaFilterActor(modelContainer: modelContext.container)
        var newCounts: [NavigationCategory: Int] = [:]
        var newCustomCounts: [UUID: Int] = [:]
        
        for cat in smartCategories {
            do {
                let result = try await actor.filterAndSort(
                    category: cat,
                    searchText: "",
                    sortOrder: .alphabetical,
                    network: nil,
                    language: nil,
                    genre: nil,
                    year: nil,
                    state: nil,
                    badge: nil,
                    limit: 1,
                    offset: 0
                )
                newCounts[cat] = result.totalCount
            } catch {
                AppLogger.debug("Error fetching count for \(cat.rawValue): \(error)")
            }
        }
        
        for collection in customSmartCollections {
            do {
                let result = try await actor.filterAndSort(
                    category: .all,
                    searchText: "",
                    sortOrder: .alphabetical,
                    network: nil,
                    language: nil,
                    genre: nil,
                    year: nil,
                    state: nil,
                    badge: nil,
                    collectionID: collection.id,
                    limit: 1,
                    offset: 0
                )
                newCustomCounts[collection.id] = result.totalCount
            } catch {
                AppLogger.debug("Error fetching count for smart collection \(collection.name): \(error)")
            }
        }
        
        await HubCountsCache.shared.save(counts: newCounts, customCounts: newCustomCounts)
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.3)) {
                self.counts = newCounts
                self.customSmartCounts = newCustomCounts
                self.countsLoaded = true
            }
        }
    }

    private func togglePinned(_ category: NavigationCategory) {
        var pinned = pinnedSystemCategories.split(separator: ",").map(String.init)
        if let index = pinned.firstIndex(of: category.rawValue) {
            pinned.remove(at: index)
        } else {
            pinned.append(category.rawValue)
        }
        pinnedSystemCategories = pinned.joined(separator: ",")
    }
}

private struct SmartCollectionCard: View {
    var collection: MediaCollection? = nil
    let title: String
    let icon: String
    let description: String
    let count: Int?
    let accentColor: Color
    var isPinned: Bool = false
    var onPinToggle: (() -> Void)? = nil
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var showingEditSheet = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(accentColor.opacity(0.12))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: icon)
                            .font(.title2)
                            .foregroundStyle(accentColor.gradient)
                    }
                    
                    Spacer()
                    
                    if let count {
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        } else {
                            Text("0")
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary.opacity(0.4))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accentColor.opacity(0.08))
                            .frame(width: 32, height: 18)
                            .skeletonPulse()
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                    
                    Text(description)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.thinMaterial)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.primary.opacity(isHovered ? 0.04 : 0.015))
                    }
                    .shadow(color: Color.black.opacity(isHovered ? 0.06 : 0), radius: isHovered ? 10 : 0, y: isHovered ? 5 : 0)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(isHovered ? 0.12 : 0.05), lineWidth: 0.8)
                    }
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(AppTheme.Animation.springSnappy, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let collection = collection {
                Button {
                    withAnimation { collection.isPinned.toggle() }
                } label: {
                    Label(collection.isPinned ? "Unpin from Sidebar" : "Pin to Sidebar", systemImage: collection.isPinned ? "pin.slash.fill" : "pin")
                }
                
                Button {
                    showingEditSheet = true
                } label: {
                    Label("Edit Collection", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    modelContext.delete(collection)
                } label: {
                    Label("Delete Collection", systemImage: "trash")
                }
            } else if onPinToggle != nil {
                Button {
                    onPinToggle?()
                } label: {
                    Label(isPinned ? "Unpin from Sidebar" : "Pin to Sidebar", systemImage: isPinned ? "pin.slash.fill" : "pin")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let collection = collection {
                CreateCollectionSheet(editingCollection: collection)
            }
        }
    }
    
    private func actionButtons(for collection: MediaCollection) -> some View {
        HStack(spacing: 4) {
            actionButton(icon: collection.isPinned ? "pin.fill" : "pin", color: collection.isPinned ? .blue : .primary) {
                withAnimation { collection.isPinned.toggle() }
            }
            
            actionButton(icon: "pencil", color: .primary) {
                showingEditSheet = true
            }
            
            actionButton(icon: "trash", color: .red) {
                modelContext.delete(collection)
            }
        }
        .padding(4)
        .background {
            Capsule().fill(.ultraThinMaterial)
        }
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
    }
    
    private func actionButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(Color.primary.opacity(0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
