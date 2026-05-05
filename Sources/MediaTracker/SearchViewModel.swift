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
        
        // 1. Try Cache First
        if let cached = fetchCachedResults(query: text, type: selectedType) {
            self.movieResults = cached.filter { $0.type == .movie }
            self.tvResults = cached.filter { $0.type == .tvShow }
            
            // Also need local search results even if cache exists
            let local = await performLocalSearch(text: text, selectedType: selectedType)
            self.filteredLocalResults = local
            
            self.isSearching = false
            self.isOfflineResultsOnly = true // Mark as offline if we didn't hit network yet
            
            // If cache is very fresh (e.g. < 5 mins), skip network. Otherwise, continue in background.
            if let first = aliasSearchTimestamp[text], Date().timeIntervalSince(first) < 300 {
                return 
            }
        }

        do {
            // Parallel Search: Local + Web
            async let localSearch = performLocalSearch(text: text, selectedType: selectedType)

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
            
            // 2. Save to Cache
            saveToCache(query: text, type: selectedType, results: movies + tv)
        }
    }

    private func performLocalSearch(text: String, selectedType: SearchType) async -> [MediaThumbnailMetadata] {
        let category: NavigationCategory
        switch selectedType {
        case .all: category = .all
        case .movie: category = .movie
        case .tvShow: category = .tvShow
        }
        let filterActor = MediaFilterActor(modelContainer: modelContainer)
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
    }

    private var aliasSearchTimestamp: [String: Date] = [:]

    private func fetchCachedResults(query: String, type: SearchType) -> [MediaSearchResult]? {
        let key = "\(type.rawValue)_\(query)"
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<SearchCacheEntity>(predicate: #Predicate { $0.key == key })
        
        if let cache = try? context.fetch(descriptor).first {
            // Check expiry (24 hours)
            if Date().timeIntervalSince(cache.timestamp) < (24 * 3600) {
                aliasSearchTimestamp[query] = cache.timestamp
                return try? JSONDecoder().decode([MediaSearchResult].self, from: cache.resultsData)
            }
        }
        return nil
    }

    private func saveToCache(query: String, type: SearchType, results: [MediaSearchResult]) {
        let context = ModelContext(modelContainer)
        let key = "\(type.rawValue)_\(query)"
        
        // Use background task to not block UI
        Task.detached(priority: .background) { [context, key, query, type, results] in
            // Remove old if exists
            try? context.delete(model: SearchCacheEntity.self, where: #Predicate { $0.key == key })
            
            if let data = try? JSONEncoder().encode(results) {
                let cache = SearchCacheEntity(query: query, type: type.rawValue, resultsData: data)
                context.insert(cache)
                try? context.save()
            }
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
