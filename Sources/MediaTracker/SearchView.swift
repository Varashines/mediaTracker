import SwiftData
import SwiftUI

enum SearchType: String, CaseIterable {
    case all = "All"
    case movie = "Movies"
    case tvShow = "TV Shows"
}

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var existingItems: [MediaItem]

    @Binding var searchText: String
    @Binding var isSearchActive: Bool
    var submitTrigger: Int
    @State private var selectedType: SearchType = .all
    @State private var resultsCount = 0  // Used to trigger staggered animations

    @State private var movieResults: [MediaSearchResult] = []
    @State private var tvResults: [MediaSearchResult] = []
    @State private var localResults: [MediaItem] = []

    @State private var trendingMovies: [MediaSearchResult] = []
    @State private var trendingTV: [MediaSearchResult] = []

    @State private var isSearching = false
    @State private var isOfflineResultsOnly = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var searchTask: Task<Void, Never>?
    @State private var cachedLibraryLookup: Set<String> = []

    private func updateLibraryLookup() {
        self.cachedLibraryLookup = Set(existingItems.map { "\($0.id)_\($0.type?.rawValue ?? "")" })
    }

    var onSelectLocal: ((MediaItem) -> Void)?

    private var allWebResults: [MediaSearchResult] {
        let lookup = cachedLibraryLookup
        var results: [MediaSearchResult] = []
        
        if selectedType == .all || selectedType == .movie {
            results.append(
                contentsOf: movieResults.filter { !lookup.contains("\($0.id)_\(MediaType.movie.rawValue)") }.prefix(10))
        }
        if selectedType == .all || selectedType == .tvShow {
            results.append(
                contentsOf: tvResults.filter { !lookup.contains("\($0.id)_\(MediaType.tvShow.rawValue)") }.prefix(10))
        }
        return results
    }

    init(
        searchText: Binding<String>, isSearchActive: Binding<Bool>, submitTrigger: Int,
        initialType: MediaType? = nil, onSelectLocal: ((MediaItem) -> Void)? = nil
    ) {
        self._searchText = searchText
        self._isSearchActive = isSearchActive
        self.submitTrigger = submitTrigger
        self.onSelectLocal = onSelectLocal
        if let type = initialType {
            let searchType: SearchType
            switch type {
            case .movie: searchType = .movie
            case .tvShow: searchType = .tvShow
            }
            _selectedType = State(initialValue: searchType)
        } else {
            _selectedType = State(initialValue: .all)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Picker("Media Type", selection: $selectedType) {
                    ForEach(SearchType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }
            .overlay(alignment: .bottom) {
                Divider()
            }

            if isOfflineResultsOnly {
                HStack {
                    Image(systemName: "wifi.slash")
                    Text("Offline: showing library results only")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    if !searchText.isEmpty && !localResults.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("From Library")
                                .font(.title2.bold())
                                .padding(.horizontal, 20)

                            let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(localResults) { item in
                                    MediaThumbnailView(item: item, mode: .grid, showTypeBadge: true) {
                                        isSearchActive = false
                                        onSelectLocal?(item)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        Divider().padding(.horizontal, 20)
                    }

                    if searchText.isEmpty {
                        let lookup = cachedLibraryLookup
                        VStack(spacing: 0) {
                            if selectedType == .all || selectedType == .movie {
                                let items = trendingMovies.filter {
                                    !lookup.contains("\($0.id)_\(MediaType.movie.rawValue)")
                                }
                                webSection(title: "Trending Movies", items: items)
                            }
                            if selectedType == .all || selectedType == .tvShow {
                                let items = trendingTV.filter {
                                    !lookup.contains("\($0.id)_\(MediaType.tvShow.rawValue)")
                                }
                                webSection(title: "Trending TV Shows", items: items)
                            }
                        }
                    } else if !allWebResults.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("From Web")
                                .font(.title2.bold())
                                .padding(.horizontal, 20)

                            let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(allWebResults) { result in
                                    MediaThumbnailView(result: result, isLocal: false) {
                                        addMedia(result)
                                    }
                                    .transition(.opacity)
                                    .animation(.spring(duration: 0.5), value: allWebResults.count)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .padding(.vertical, 20)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            searchTask?.cancel()
            if newValue.isEmpty {
                movieResults = []
                tvResults = []
                localResults = []
                loadTrending()
            } else {
                searchTask = Task { await performSearch() }
            }
        }
        .onChange(of: submitTrigger) { oldValue, newValue in
            searchTask?.cancel()
            searchTask = Task { await performSearch() }
        }
        .onChange(of: selectedType) { oldValue, newValue in
            searchTask?.cancel()
            searchTask = Task { await performSearch() }
        }
        .alert("Search Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .onAppear {
            updateLibraryLookup()
            loadTrending()
        }
        .onDisappear {
            searchTask?.cancel()
        }
        .onChange(of: existingItems) {
            updateLibraryLookup()
        }
    }

    @ViewBuilder
    private func webSection(title: String, items: [MediaSearchResult]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                let columns = [
                    GridItem(.adaptive(minimum: 160), spacing: 20, alignment: .top)
                ]

                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(items) { result in
                        MediaThumbnailView(result: result, isLocal: false) {
                            addMedia(result)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 24)
        }
    }

    private func loadTrending() {
        Task {
            do {
                let movies = try await APIClient.shared.fetchTrendingMovies()
                let tv = try await APIClient.shared.fetchTrendingTVShows()
                await MainActor.run {
                    trendingMovies = movies
                    trendingTV = tv
                }
            } catch {
                print("Error loading trending: \(error)")
            }
        }
    }

    private func performSearch() async {
        // Skip searching if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        guard !searchText.isEmpty else {
            movieResults = []
            tvResults = []
            localResults = []
            isOfflineResultsOnly = false
            return
        }
        
        // 1. Debounce to prevent UI lag while typing
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        
        isSearching = true
        isOfflineResultsOnly = false
        
        // 2. Perform Local Filter (off-main logic where possible)
        let currentSearch = searchText
        let currentType = selectedType
        let items = existingItems
        
        let searchLower = currentSearch.lowercased()
        let filteredLocal = items.filter { item in
            let matchesText = item.searchableText.contains(searchLower)
            let matchesType: Bool
            switch currentType {
            case .all: matchesType = true
            case .movie: matchesType = item.type == .movie
            case .tvShow: matchesType = item.type == .tvShow
            }
            return matchesText && matchesType
        }

        // Show local results immediately
        await MainActor.run {
            self.localResults = filteredLocal
        }

        do {
            var movies: [MediaSearchResult] = []
            var tv: [MediaSearchResult] = []

            if selectedType == .all || selectedType == .movie {
                movies = try await APIClient.shared.searchMovies(query: currentSearch)
            }

            if selectedType == .all || selectedType == .tvShow {
                tv = try await APIClient.shared.searchTVShows(query: currentSearch)
            }

            let finalMovies = movies
            let finalTV = tv

            if Task.isCancelled { return }

            await MainActor.run {
                self.movieResults = finalMovies
                self.tvResults = finalTV
                self.isSearching = false
                self.isOfflineResultsOnly = false
                withAnimation {
                    self.resultsCount += 1
                }
            }
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                await MainActor.run { self.isSearching = false }
                return
            }
            
            await MainActor.run {
                self.isSearching = false
                // Only show error if we have no local results to show
                if self.localResults.isEmpty {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    self.isOfflineResultsOnly = false
                } else {
                    print("Offline search: showing local results only. Error: \(error.localizedDescription)")
                    self.isOfflineResultsOnly = true
                }
            }
        }
    }

    @MainActor
    private func addMedia(_ result: MediaSearchResult) {
        Task {
            let releaseDate =
                result.releaseDate != nil ? DateUtils.parseDate(result.releaseDate) : nil
            let item = MediaItem(
                id: result.id, title: result.title, overview: result.overview,
                posterURL: result.posterURL, releaseDate: releaseDate, type: result.type)
            item.dateAdded = Date()

            if result.type == .movie, let tmdbID = Int(result.id) {
                let details = try? await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                if let details = details {
                    item.releaseDate = DateUtils.parseDate(details.releaseDate)
                    item.movieDetails = MovieDetails(
                        tmdbID: tmdbID, 
                        runtime: details.runtime, 
                        genres: details.genres,
                        voteAverage: details.voteAverage,
                        originalLanguage: details.originalLanguage
                    )
                }
            } else if result.type == .tvShow, let tmdbID = Int(result.id) {
                let details = try? await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
                if let details = details {
                    let tvDetails = TVShowDetails(
                        tmdbID: tmdbID,
                        status: details.status,
                        network: details.network,
                        networkLogoPath: details.networkLogoPath,
                        originalLanguage: details.originalLanguage,
                        numberOfSeasons: details.seasonsCount,
                        numberOfEpisodes: details.episodesCount,
                        voteAverage: details.voteAverage,
                        genres: details.genres
                    )
                    tvDetails.seasons = details.seasons.map { season in
                        TVSeason(
                            seasonNumber: season.season_number, name: season.name,
                            episodeCount: season.episode_count, airDate: season.air_date)
                    }
                    tvDetails.tvdbID = details.tvdbID
                    item.tvShowDetails = tvDetails
                }
            }

            item.updateSearchableText()
            modelContext.insert(item)
            try? modelContext.save() // FORCE PERMANENCE
            onSelectLocal?(item)
        }
    }
}
