import SwiftUI
import SwiftData

struct ActorDestination: Hashable {
    let actorName: String
}

struct ActorFilmographyView: View {
    let actorName: String
    @Environment(\.modelContext) private var modelContext
    @State private var items: [MediaItem] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 300)
            } else if items.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 50))
                        .foregroundStyle(.secondary.opacity(0.3))
                    Text("No items found featuring \(actorName)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 300)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 20) {
                    ForEach(items, id: \.persistentModelID) { item in
                        NavigationLink(value: item) {
                            MediaThumbnailView(
                                item: item,
                                mode: .grid,
                                showTypeBadge: true,
                                isFastScrolling: false
                            )
                        }
                        .buttonStyle(.interactive)
                    }
                }
                .padding(40)
            }
        }
        .navigationTitle("\(actorName) Filmography")
        .task { await fetchItems() }
    }

    private func fetchItems() async {
        let descriptor = FetchDescriptor<CastMember>(predicate: #Predicate { $0.name == actorName })
        guard let castMembers = try? modelContext.fetch(descriptor) else {
            isLoading = false
            return
        }
        var seen = Set<PersistentIdentifier>()
        for member in castMembers {
            if let movie = member.movieDetails?.item, !seen.contains(movie.persistentModelID) {
                seen.insert(movie.persistentModelID)
                items.append(movie)
            }
            if let tv = member.tvShowDetails?.item, !seen.contains(tv.persistentModelID) {
                seen.insert(tv.persistentModelID)
                items.append(tv)
            }
        }
        withAnimation(.easeInOut(duration: 0.25)) { isLoading = false }
    }
}
