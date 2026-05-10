import SwiftUI
import SwiftData

struct SmartCollectionsHubView: View {
    let namespace: Namespace.ID
    @Binding var selection: SidebarItem?
    
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @AppStorage("pinned_system_categories") private var pinnedSystemCategories: String = ""
    
    @State private var counts: [NavigationCategory: Int] = [:]
    @State private var customSmartCounts: [UUID: Int] = [:]
    @State private var showingCreateSheet = false
    @State private var initialIsSmart = true
    
    @Query(filter: #Predicate<MediaCollection> { $0.isSmart == true })
    private var customSmartCollections: [MediaCollection]
    
    @Query(filter: #Predicate<MediaCollection> { $0.isSmart == false })
    private var manualCollections: [MediaCollection]
    
    private let smartCategories: [NavigationCategory] = [
        .releaseRadar, .catchUp, .loved, .binge, .quickBites, .stalled, .archive
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 35) {
                // 1. SYSTEM SMART COLLECTIONS
                sectionHeaderMini("System Intelligence")
                    .padding(.horizontal, 40)
                    .padding(.top, 40)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 25)], spacing: 25) {
                    let pinnedList = pinnedSystemCategories.split(separator: ",").map(String.init)
                    ForEach(smartCategories) { category in
                        SmartCollectionCard(
                            title: category.title,
                            icon: category.icon,
                            description: description(for: category),
                            count: counts[category] ?? 0,
                            accentColor: appAccent.color,
                            isPinned: pinnedList.contains(category.rawValue),
                            onPinToggle: { togglePinned(category) }
                        ) {
                            selection = .category(category)
                        }
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
                                count: customSmartCounts[collection.id] ?? 0,
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
            await fetchCounts()
        }
    }
    
    private func sectionHeaderMini(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(.secondary)
            .kerning(2)
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
        case .catchUp: return "Shows with backlogs and new episodes airing this week."
        case .loved: return "Your absolute favorites, marked with a heart."
        case .binge: return "Shows with multiple unwatched episodes available."
        case .quickBites: return "Short media under 90 minutes for quick viewing."
        case .stalled: return "Active titles with no progress in the last 3 months."
        case .archive: return "Completed or dropped items you've archived."
        default: return ""
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
                    limit: 1,
                    offset: 0
                )
                newCounts[cat] = result.totalCount
            } catch {
                print("Error fetching count for \(cat.rawValue): \(error)")
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
                    collectionID: collection.id,
                    limit: 1,
                    offset: 0
                )
                newCustomCounts[collection.id] = result.totalCount
            } catch {
                print("Error fetching count for smart collection \(collection.name): \(error)")
            }
        }
        
        await MainActor.run {
            withAnimation(.smooth) {
                self.counts = newCounts
                self.customSmartCounts = newCustomCounts
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
    let count: Int
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
                    
                    Text("\(count)")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary.opacity(0.8))
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
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(colorScheme == .dark 
                          ? accentColor.opacity(isHovered ? 0.08 : 0.04) 
                          : Color(NSColor.controlBackgroundColor).opacity(isHovered ? 1.0 : 0.85))
                    .shadow(color: colorScheme == .dark 
                            ? accentColor.opacity(isHovered ? 0.2 : 0)
                            : Color(red: 0, green: 0.1, blue: 0.3).opacity(isHovered ? 0.12 : 0.05), 
                            radius: isHovered ? 15 : 10, x: 0, y: isHovered ? 10 : 5)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(colorScheme == .dark 
                                    ? accentColor.opacity(isHovered ? 0.4 : 0.15) 
                                    : Color(red: 0, green: 0.1, blue: 0.3).opacity(isHovered ? 0.15 : 0.08), lineWidth: 1)
                    }
            }
            .overlay(alignment: .topTrailing) {
                if isHovered {
                    if let collection = collection {
                        actionButtons(for: collection)
                            .padding(12)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        // System category pinning
                        actionButton(icon: isPinned ? "pin.fill" : "pin", color: isPinned ? .blue : .primary) {
                            onPinToggle?()
                        }
                        .padding(4)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
        .background(.ultraThinMaterial)
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
