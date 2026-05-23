import SwiftUI
import SwiftData

struct FilteredLibraryGridView: View {
    let filter: DiscoveryFilter
    let namespace: Namespace.ID
    @Binding var isFastScrolling: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var items: [MediaThumbnailMetadata] = []
    @State private var networkColor: Color? = nil
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let columns = [GridItem(.adaptive(minimum: 160), spacing: 25, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(items) { metadata in
                        NavigationLink(value: metadata.id) {
                            MediaThumbnailView(
                                metadata: metadata, mode: .grid, namespace: namespace,
                                isFastScrolling: isFastScrolling)
                        }
                        .buttonStyle(.interactive)
                    }
                }
            }
            .padding(30)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            if let color = networkColor {
                color.opacity(colorScheme == .dark ? 0.08 : 0.04)
                    .ignoresSafeArea()
            }
        }
        .navigationTitle(filter.type == .language ? LanguageUtils.languageName(for: filter.name) : filter.name)
        .onChange(of: MediaStateService.shared.needsFullRefreshCount) { _, _ in
            let itemID = MediaStateService.shared.lastChangedItemID
            if let itemID = itemID {
                updateSingleItem(id: itemID)
            } else {
                fetchItems()
            }
        }
        .task {
            fetchItems()
            if filter.type == .studio {
                fetchNetworkColor()
            }
        }
    }

    private func fetchNetworkColor() {
        let name = filter.name
        let descriptor = FetchDescriptor<NetworkEntity>(predicate: #Predicate { $0.name == name })
        if let network = try? modelContext.fetch(descriptor).first, let hex = network.themeColorHex {
            self.networkColor = Color(hex: hex)
        }
    }

    private func fetchItems() {
        Task {
            let filterActor = MediaFilterActor(modelContainer: modelContext.container)
            var network: [String]? = nil
            var language: String? = nil
            var genre: String? = nil
            var badge: String? = nil
            var sortOrder: SortOrder = .alphabetical
            
            switch filter.type {
            case .studio: network = filter.sourceNames ?? [filter.name]
            case .genre: genre = filter.name
            case .language: language = filter.name
            case .badge: 
                badge = filter.name
                sortOrder = .recentInteraction
            }
            
            do {
                let result = try await filterActor.filterAndSort(
                    category: .all,
                    searchText: "",
                    sortOrder: sortOrder,
                    network: network,
                    language: language,
                    genre: genre,
                    badge: badge,
                    limit: 1000,
                    offset: 0
                )
                await MainActor.run {
                    withAnimation {
                        self.items = result.displayed
                    }
                }
            } catch {
                print("Error fetching filtered items: \(error)")
            }
        }
    }

    private func updateSingleItem(id: PersistentIdentifier) {
        let container = modelContext.container
        var network: [String]? = nil
        var language: String? = nil
        var genre: String? = nil
        var badge: String? = nil
        
        switch filter.type {
        case .studio: network = filter.sourceNames ?? [filter.name]
        case .genre: genre = filter.name
        case .language: language = filter.name
        case .badge: badge = filter.name
        }
        
        Task {
            do {
                let filterActor = MediaFilterActor(modelContainer: container)
                let updatedMetadata = try await filterActor.fetchMetadataIfMatches(
                    for: id,
                    category: .all,
                    searchText: "",
                    network: network,
                    language: language,
                    genre: genre,
                    badge: badge
                )
                
                await MainActor.run {
                    withAnimation(AppTheme.Animation.easeInOut) {
                        if let index = items.firstIndex(where: { $0.id == id }) {
                            if let updated = updatedMetadata {
                                items[index] = updated
                            } else {
                                items.remove(at: index)
                            }
                        } else if let updated = updatedMetadata {
                            items.append(updated)
                            
                            // Re-sort the items list
                            switch filter.type {
                            case .badge:
                                items.sort { ($0.lastInteractionDate ?? Date.distantPast) > ($1.lastInteractionDate ?? Date.distantPast) }
                            default:
                                items.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
                            }
                        }
                    }
                }
            } catch {
                print("Error updating single item in FilteredLibraryGridView: \(error)")
            }
        }
    }
}
