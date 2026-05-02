import SwiftUI
import SwiftData

struct FilteredLibraryGridView: View {
    let filter: DiscoveryFilter
    let namespace: Namespace.ID
    @Binding var isFastScrolling: Bool
    @AppStorage("app_accent") private var appAccent: AppAccent = .cosmic
    @Environment(\.modelContext) private var modelContext

    @State private var items: [MediaThumbnailMetadata] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let columns = [GridItem(.adaptive(minimum: 160), spacing: 25, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(items) { metadata in
                        if let item = modelContext.model(for: metadata.id) as? MediaItem, !item.isDeleted {
                            NavigationLink(value: item) {
                                MediaThumbnailView(
                                    metadata: metadata, mode: .grid, namespace: namespace,
                                    isFastScrolling: isFastScrolling)
                            }
                            .buttonStyle(.interactive)
                        }
                    }
                }
            }
            .padding(30)
        }
        .navigationTitle(filter.type == .language ? LanguageUtils.languageName(for: filter.name) : filter.name)
        .onReceive(NotificationCenter.default.publisher(for: .mediaItemRefreshed)) { _ in
            fetchItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mediaStateChanged)) { _ in
            fetchItems()
        }
        .task {
            fetchItems()
        }
    }

    private func fetchItems() {
        Task {
            let filterActor = MediaFilterActor(modelContainer: modelContext.container)
            var network: [String]? = nil
            var language: String? = nil
            var genre: String? = nil
            
            switch filter.type {
            case .studio: network = filter.sourceNames ?? [filter.name]
            case .genre: genre = filter.name
            case .language: language = filter.name
            }
            
            do {
                let result = try await filterActor.filterAndSort(
                    category: .all,
                    searchText: "",
                    sortOrder: .alphabetical,
                    network: network,
                    language: language,
                    genre: genre,
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
}
