import SwiftUI
import Combine

struct FilterSnapshot: Sendable, Hashable {
    let category: NavigationCategory
    let searchText: String
    let sortOrder: SortOrder
    let networks: [String]
    let languages: [String]
    let genres: [String]
    let years: [String]
    let states: [MediaState]
    let providers: [String]
    let groupBy: GroupBy
    let collectionID: UUID?

    @MainActor
    init(from viewModel: MediaViewModel) {
        self.category = viewModel.filter.selectedCategory
        self.searchText = viewModel.filter.searchText
        self.sortOrder = viewModel.filter.currentSortOrder
        self.networks = viewModel.filter.selectedNetworks
        self.languages = viewModel.filter.selectedLanguages
        self.genres = viewModel.filter.selectedGenres
        self.years = viewModel.filter.selectedYears
        self.states = viewModel.filter.selectedStates
        self.providers = viewModel.filter.selectedProviders
        self.groupBy = viewModel.filter.currentGroupBy
        self.collectionID = viewModel.collection.selectedCollectionID
    }
}

@Observable
@MainActor
class MediaViewModel {
    let filterSubject = PassthroughSubject<Void, Never>()
    var navigationPath = NavigationPath()

    var filter = FilterState()
    var pagination = PaginationState()
    var collection = CollectionState()
    var display = DisplayCache()
    var discovery = DiscoveryCache()
    var trendingMovies: [MediaSearchResult] = []
    var trendingShows: [MediaSearchResult] = []

    var onFilterUpdate: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    private var trendingTask: Task<Void, Never>?

    init() {
        filterSubject
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.onFilterUpdate?()
            }
            .store(in: &cancellables)
    }

    func navigationTitle(for category: NavigationCategory) -> String {
        if let colName = collection.selectedCollectionName {
            return colName
        }
        if let first = filter.selectedNetworks.first {
            return filter.selectedNetworks.count == 1 ? first : "Merged Studios"
        }
        if let lang = filter.selectedLanguages.first {
            return Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
        }
        return category.title
    }

    func fetchTrendingIfNeeded() {
        guard trendingMovies.isEmpty || trendingShows.isEmpty else { return }
        trendingTask?.cancel()
        trendingTask = Task { [weak self] in
            async let movies = APIClient.shared.fetchTrendingMovies()
            async let shows = APIClient.shared.fetchTrendingTVShows()
            let m = (try? await movies) ?? []
            let s = (try? await shows) ?? []
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.trendingMovies = m
                self?.trendingShows = s
            }
        }
    }

    func fetchRecommendationsIfNeeded(actor: MediaFilterActor, forceRefresh: Bool = false) {
        if !forceRefresh {
            guard display.recommendations.isEmpty else {
                display.recommendationsFetched = true
                return
            }
        }
        Task { [weak self] in
            let recs = await actor.fetchRecommendations(forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.display.recommendations = recs
                self?.display.recommendationsFetched = true
                ImageCache.shared.prewarmImages(recs, limit: 6, targetSize: .thumbSmall, priority: .low)
                let backdrops = recs.prefix(6).compactMap(\.cardBackdropURL).compactMap(URL.init(string:))
                ImageCache.shared.prewarmImages(urls: backdrops, targetSize: .backdropCompact, priority: .low)
            }
        }
    }

    func fetchPickOfTheDayIfNeeded(actor: MediaFilterActor) {
        guard display.pickOfTheDay.isEmpty else { return }
        Task { [weak self] in
            let picks = await actor.fetchPickOfTheDay()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.display.pickOfTheDay = picks
            }
        }
    }

    func purgeSleepCache() {
        display.purgeAll()
        discovery.purgeAll()
        ImageCache.shared.cancelPrewarming()
    }
}
