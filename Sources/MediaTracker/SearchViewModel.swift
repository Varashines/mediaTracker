import SwiftData
import SwiftUI
import Combine

@MainActor
@Observable
class SearchViewModel {
    var movieResults: [MediaSearchResult] = []
    var tvResults: [MediaSearchResult] = []
    var filteredLocalResults: [MediaThumbnailMetadata] = []
    var isSearching = false
    var isOfflineResultsOnly = false
    var errorMessage: String?
    var showError = false
    
    private var searchTask: Task<Void, Never>?
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func handleSearchTextChange(_ text: String, selectedType: SearchType) {
        searchTask?.cancel()
        if text.isEmpty {
            movieResults = []
            tvResults = []
            filteredLocalResults = []
        } else {
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
                await performSearch(text: text, selectedType: selectedType)
            }
        }
    }

    func performSearch(text: String, selectedType: SearchType) async {
        guard !SleepManager.shared.isAsleep else { return }
        
        isSearching = true
        isOfflineResultsOnly = false
        
        let container = modelContainer

        do {
            // Parallel Search: Local + Web
            async let localSearch: [MediaThumbnailMetadata] = {
                let filterActor = MediaFilterActor(modelContainer: container)
                let category: NavigationCategory
                switch selectedType {
                case .all: category = .all
                case .movie: category = .movie
                case .tvShow: category = .tvShow
                }
                let result = try? await filterActor.filterAndSort(
                    category: category,
                    searchText: text,
                    sortOrder: .alphabetical,
                    network: nil,
                    language: nil,
                    limit: 50,
                    offset: 0
                )
                return result?.displayed ?? []
            }()

            async let webMovies: [MediaSearchResult] = {
                if selectedType == .all || selectedType == .movie {
                    return (try? await APIClient.shared.searchMovies(query: text)) ?? []
                }
                return []
            }()

            async let webTV: [MediaSearchResult] = {
                if selectedType == .all || selectedType == .tvShow {
                    return (try? await APIClient.shared.searchTVShows(query: text)) ?? []
                }
                return []
            }()

            let (local, movies, tv) = await (localSearch, webMovies, webTV)

            if Task.isCancelled { return }

            self.filteredLocalResults = local
            self.movieResults = movies
            self.tvResults = tv
            self.isSearching = false
            self.isOfflineResultsOnly = false
        }
    }

    func addMedia(_ result: MediaSearchResult, modelContext: ModelContext, onSuccess: @escaping @MainActor (MediaItem) -> Void) {
        FeedbackManager.shared.trigger(.addToLibrary)
        let typePrefix = result.type == .movie ? "movie" : "tv"
        let uniqueID = "\(typePrefix)_\(result.id)"

        // Prevent race condition (double-click)
        if DataService.shared.isProcessing(id: uniqueID) { return }
        DataService.shared.startProcessing(id: uniqueID)

        let container = modelContainer
        let tmdbID = Int(result.id) ?? 0
        let type = result.type
        let title = result.title
        let overview = result.overview
        let poster = result.posterURL
        let release = result.releaseDate
        
        Task {
            defer { DataService.shared.stopProcessing(id: uniqueID) }

            let fetchResult = await Task.detached(priority: .userInitiated) { () -> (id: PersistentIdentifier?, isExisting: Bool) in
                let service = BackgroundDataService(modelContainer: container)
                let result = await service.createNewMediaItem(
                    uniqueID: uniqueID, 
                    tmdbID: tmdbID, 
                    type: type, 
                    title: title, 
                    overview: overview, 
                    posterURL: poster, 
                    releaseDateString: release
                )

                // Sync Discovery Entities
                if let id = result.id {
                    let sync = DiscoverySyncService(modelContainer: container)
                    let actorContext = ModelContext(container)
                    if let fetchedItem = actorContext.model(for: id) as? MediaItem {
                        await sync.updateItemAdded(fetchedItem)
                    }
                }
                
                return result
            }.value

            if fetchResult.isExisting {
                AppErrorState.shared.showToast("Title already in Library", systemImage: "info.circle.fill", type: .info)
            }
            
            if let id = fetchResult.id, let item = modelContext.model(for: id) as? MediaItem {
                onSuccess(item)
            }
        }
    }
}
