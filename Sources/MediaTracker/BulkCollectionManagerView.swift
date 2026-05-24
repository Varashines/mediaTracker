import SwiftUI
import SwiftData

struct BulkCollectionManagerView: View {
    let collection: MediaCollection
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var selectedItemIDs: Set<String> = []
    @State private var allItems: [MediaItem] = []
    @State private var isLoading = true
    
    var filteredItems: [MediaItem] {
        if searchText.isEmpty {
            return allItems
        } else {
            return allItems.filter { $0.title.lowercased().contains(searchText.lowercased()) }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Items")
                        .font(.title3.bold())
                    Text("Add or remove items from '\(collection.name)'")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("Search your library...", text: $searchText)
                        .font(.system(size: 13))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(10)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                
                if isLoading {
                    Spacer()
                    ProgressView("Loading library…")
                        .controlSize(.large)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120, maximum: 160))], spacing: 16) {
                            ForEach(filteredItems) { item in
                                BulkItemCard(item: item, isSelected: selectedItemIDs.contains(item.id)) {
                                    toggleSelection(for: item)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        saveChanges()
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                selectedItemIDs = Set(collection.items.map { $0.id })
            }
            .task {
                let container = modelContext.container
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\.title)])
                let items = (try? context.fetch(descriptor)) ?? []
                await MainActor.run {
                    allItems = items
                    isLoading = false
                }
            }
        }
        .frame(minWidth: 600, minHeight: 450, maxHeight: 650)
    }
    
    private func toggleSelection(for item: MediaItem) {
        if selectedItemIDs.contains(item.id) {
            selectedItemIDs.remove(item.id)
        } else {
            selectedItemIDs.insert(item.id)
        }
    }
    
    private func saveChanges() {
        collection.items.removeAll { item in
            !selectedItemIDs.contains(item.id)
        }
        
        for id in selectedItemIDs {
            if !collection.items.contains(where: { $0.id == id }) {
                if let item = allItems.first(where: { $0.id == id }) {
                    collection.items.append(item)
                }
            }
        }
        
        try? modelContext.save()
        MediaStateService.shared.postMediaStateChanged()
    }
}

struct BulkItemCard: View {
    let item: MediaItem
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                // Poster
                if let posterURL = item.posterURL, let url = URL(string: "https://image.tmdb.org/t/p/w300\(posterURL)") {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.primary.opacity(0.1)
                        }
                    }
                    .frame(width: 120, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 120, height: 180)
                        .overlay {
                            Image(systemName: item.type == .movie ? "film" : "tv")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                }
                
                // Selection Indicator
                Circle()
                    .fill(isSelected ? Color.blue : Color.black.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Image(systemName: isSelected ? "checkmark" : "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(8)
            }
            
            Text(item.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .onTapGesture {
            onToggle()
        }
        .padding(4)
        .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(16)
    }
}

#Preview("Bulk Collection Manager") {
    BulkCollectionManagerView(collection: {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, MediaCollection.self, configurations: config)
        let context = container.mainContext
        let collection = MediaCollection(name: "Favorites", systemImage: "heart.fill")
        context.insert(collection)
        return collection
    }())
    .modelContainer(try! ModelContainer(
        for: MediaItem.self, MediaCollection.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ))
}
