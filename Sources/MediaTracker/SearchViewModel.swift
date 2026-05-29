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
    var libraryTMDBIDs: Set<String> = []
    
    var allWebResults: [MediaSearchResult] {
        var results: [MediaSearchResult] = []
        if libraryTMDBIDs.isEmpty {
            results.append(contentsOf: movieResults.prefix(15))
            results.append(contentsOf: tvResults.prefix(15))
        } else {
            results.append(contentsOf: movieResults.filter { !libraryTMDBIDs.contains("movie_\($0.id)") }.prefix(15))
            results.append(contentsOf: tvResults.filter { !libraryTMDBIDs.contains("tv_\($0.id)") }.prefix(15))
        }
        return results
    }
    
    private var searchTask: Task<Void, Never>?
    private let modelContainer: ModelContainer
    private var cancellables = Set<AnyCancellable>()

    private func getFilterActor() -> MediaFilterActor {
        MediaFilterActor.shared(modelContainer: modelContainer)
    }
    private let searchSubject = PassthroughSubject<(String, SearchType), Never>()

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        setupSearchDebounce()
    }

    private func setupSearchDebounce() {
        searchSubject
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] text, selectedType in
                self?.searchTask?.cancel()
                self?.searchTask = Task {
                    await self?.performSearch(text: text, selectedType: selectedType)
                }
            }
            .store(in: &cancellables)
    }

    func handleSearchTextChange(_ text: String, selectedType: SearchType) {
        if text.isEmpty {
            cancelAllSearchOperations()
        } else {
            searchSubject.send((text, selectedType))
        }
    }

    func triggerSearch(text: String, selectedType: SearchType) {
        searchTask?.cancel()
        searchTask = Task {
            await performSearch(text: text, selectedType: selectedType)
        }
    }
    
    func cancelAllSearchOperations() {
        searchTask?.cancel()
        searchTask = nil
        movieResults = []
        tvResults = []
        filteredLocalResults = []
        isSearching = false
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

            async let webMovies: [MediaSearchResult]? = {
                if selectedType == .all || selectedType == .movie {
                    return try? await APIClient.shared.searchMovies(query: text)
                }
                return []
            }()

            async let webTV: [MediaSearchResult]? = {
                if selectedType == .all || selectedType == .tvShow {
                    return try? await APIClient.shared.searchTVShows(query: text)
                }
                return []
            }()

            let (local, movies, tv) = await (localSearch, webMovies, webTV)

            if Task.isCancelled { return }

            self.filteredLocalResults = local
            
            var hasNewResults = false
            if let movies = movies {
                self.movieResults = movies
                hasNewResults = true
            }
            if let tv = tv {
                self.tvResults = tv
                hasNewResults = true
            }
            
            if movies == nil || tv == nil {
                self.errorMessage = "Offline or search failed. Displaying cached results."
                self.showError = true
            } else {
                self.errorMessage = nil
                self.showError = false
            }
            
            self.isSearching = false
            self.isOfflineResultsOnly = (movies == nil || tv == nil)
            
            // 2. Save to Cache only if we successfully retrieved new results
            if hasNewResults, let fetchedMovies = movies, let fetchedTV = tv {
                saveToCache(query: text, type: selectedType, results: fetchedMovies + fetchedTV)
            }
        }
    }

    private func performLocalSearch(text: String, selectedType: SearchType) async -> [MediaThumbnailMetadata] {
        let category: NavigationCategory
        switch selectedType {
        case .all: category = .all
        case .movie: category = .movie
        case .tvShow: category = .tvShow
        }
        let filterActor = getFilterActor()
        let result = try? await filterActor.filterAndSort(
            category: category,
            searchText: text,
            sortOrder: .alphabetical,
            network: nil,
            language: nil,
            genre: nil,
            year: nil,
            state: nil,
            badge: nil,
            limit: 200,
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
        let container = modelContainer
        let key = "\(type.rawValue)_\(query)"
        
        // Use background task to not block UI
        Task.detached(priority: .background) { [container, key, query, type, results] in
            let context = ModelContext(container)
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
                    await sync.updateItemAdded(id)
                }
                
                return result
            }.value

            if fetchResult.isExisting {
                AppErrorState.shared.showToast("Title already in Library", style: .info)
            }
            
            if let id = fetchResult.id, let item = modelContext.model(for: id) as? MediaItem {
                onSuccess(item)
            }
        }
    }
}
