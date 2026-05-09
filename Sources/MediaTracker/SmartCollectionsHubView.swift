import SwiftUI
import SwiftData

struct SmartCollectionsHubView: View {
    let namespace: Namespace.ID
    @Binding var selection: SidebarItem?
    
    @Environment(\.modelContext) private var modelContext
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    
    @State private var counts: [NavigationCategory: Int] = [:]
    @State private var customSmartCounts: [UUID: Int] = [:]
    @State private var showingCreateSheet = false
    
    @Query(filter: #Predicate<MediaCollection> { $0.isSmart == true })
    private var customSmartCollections: [MediaCollection]
    
    private let smartCategories: [NavigationCategory] = [
        .releaseRadar, .catchUp, .quickBites, .stalled
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 35) {
                // 1. SYSTEM SMART COLLECTIONS
                sectionHeaderMini("System Filters")
                    .padding(.horizontal, 40)
                    .padding(.top, 40)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 25)], spacing: 25) {
                    ForEach(smartCategories) { category in
                        SmartCollectionCard(
                            title: category.title,
                            icon: category.icon,
                            description: description(for: category),
                            count: counts[category] ?? 0,
                            accentColor: appAccent.color
                        ) {
                            selection = .category(category)
                        }
                    }
                }
                .padding(.horizontal, 40)
                
                // 2. CUSTOM SMART PLAYLISTS
                sectionHeaderMini("Smart Playlists")
                    .padding(.horizontal, 40)
                    .padding(.top, 20)
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 25)], spacing: 25) {
                    // Create New Smart Playlist Card
                    Button {
                        showingCreateSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.purple.opacity(0.1))
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(.purple.gradient)
                                }
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("New Smart Playlist")
                                    .font(.system(.headline, design: .rounded))
                                Text("Define rules to automatically group media.")
                                    .font(.system(size: 12, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.purple.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [6]))
                        }
                    }
                    .buttonStyle(.plain)

                    ForEach(customSmartCollections) { collection in
                        SmartCollectionCard(
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
                .padding(.horizontal, 40)
                
                Spacer(minLength: 50)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $showingCreateSheet) {
            CreateCollectionSheet(initialIsSmart: true)
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

    private func description(for category: NavigationCategory) -> String {
        switch category {
        case .releaseRadar: return "Recently released episodes and movies from your library."
        case .catchUp: return "Shows with backlogs and new episodes airing this week."
        case .quickBites: return "Short media under 90 minutes for quick viewing."
        case .stalled: return "Active titles with no progress in the last 3 months."
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
}

private struct SmartCollectionCard: View {
    let title: String
    let icon: String
    let description: String
    let count: Int
    let accentColor: Color
    let action: () -> Void
    
    @State private var isHovered = false
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
                    .fill(Color.primary.opacity(isHovered ? (colorScheme == .dark ? 0.05 : 0.03) : (colorScheme == .dark ? 0.03 : 0.015)))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(accentColor.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
                    }
            }
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
