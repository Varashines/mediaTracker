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
    var viewModel: MediaViewModel
    @State private var selectedType: SearchType = .all
    @State private var resultsCount = 0

    @State private var movieResults: [MediaSearchResult] = []
    @State private var tvResults: [MediaSearchResult] = []

    private var filteredLocalResults: [MediaItem] {
        if searchText.isEmpty { return [] }
        
        let processedSearchText = searchText.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ":", with: "")
        
        let searchTokens = processedSearchText.split(separator: " ").map(String.init)
        return existingItems.filter { item in
            guard !item.isDeleted else { return false }
            let target = item.searchableText
            let matchesText = searchTokens.allSatisfy { target.contains($0) }
            
            let matchesType: Bool
            switch selectedType {
            case .all: matchesType = true
            case .movie: matchesType = item.type == .movie
            case .tvShow: matchesType = item.type == .tvShow
            }
            return matchesText && matchesType
        }
    }

    @State private var isSearching = false
    @State private var isOfflineResultsOnly = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var searchTask: Task<Void, Never>?

    private var allWebResults: [MediaSearchResult] {
        let lookup = Set(existingItems.map { "\($0.id)_\($0.type?.rawValue ?? "")" })
        var results: [MediaSearchResult] = []
        
        if selectedType == .all || selectedType == .movie {
            results.append(
                contentsOf: movieResults.filter { !lookup.contains("\($0.id)_\(MediaType.movie.rawValue)") }.prefix(15))
        }
        if selectedType == .all || selectedType == .tvShow {
            results.append(
                contentsOf: tvResults.filter { !lookup.contains("\($0.id)_\(MediaType.tvShow.rawValue)") }.prefix(15))
        }
        return results
    }

    init(
        searchText: Binding<String>, isSearchActive: Binding<Bool>, submitTrigger: Int,
        initialType: MediaType? = nil, viewModel: MediaViewModel, onSelectLocal: ((MediaItem) -> Void)? = nil
    ) {
        self._searchText = searchText
        self._isSearchActive = isSearchActive
        self.submitTrigger = submitTrigger
        self.viewModel = viewModel
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

    var onSelectLocal: ((MediaItem) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // PINNED HEADER: Fixed to top to prevent collisions
            VStack(spacing: 12) {
                HStack {
                    Text("Media Type")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    
                    Picker("Media Type", selection: $selectedType) {
                        ForEach(SearchType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    
                    Spacer()
                    
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 10)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 16)
                
                Divider().padding(.horizontal, 30)
            }
            .background(.ultraThinMaterial)
            .zIndex(10) // Keep header above scroll content

            if isOfflineResultsOnly {
                HStack {
                    Image(systemName: "wifi.slash")
                    Text("Offline: showing library results only")
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    // SECTION 1: Local Library Results
                    if !searchText.isEmpty && !filteredLocalResults.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Image(systemName: "tray.full.fill")
                                    .foregroundStyle(.secondary)
                                Text("In Your Library")
                                    .font(.title3.bold())
                            }
                            .padding(.horizontal, 30)

                            let columns = [GridItem(.adaptive(minimum: 160), spacing: 25, alignment: .top)]
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                                ForEach(filteredLocalResults) { item in
                                    MediaThumbnailView(item: item, mode: .grid, showTypeBadge: true) {
                                        isSearchActive = false
                                        onSelectLocal?(item)
                                    }
                                    .id("local_\(item.id)")
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                        
                        Divider().padding(.horizontal, 30)
                    }

                    // SECTION 2: Global Web Results
                    if searchText.isEmpty {
                        VStack(spacing: 40) {
                            if selectedType == .all || selectedType == .movie {
                                webSection(title: "Trending Movies", icon: "flame.fill", items: filterExisting(viewModel.trendingMovies))
                            }
                            if selectedType == .all || selectedType == .tvShow {
                                webSection(title: "Trending TV Shows", icon: "sparkles", items: filterExisting(viewModel.trendingTV))
                            }
                        }
                    } else if !allWebResults.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Image(systemName: "globe")
                                    .foregroundStyle(.secondary)
                                Text("Global Search")
                                    .font(.title3.bold())
                            }
                            .padding(.horizontal, 30)

                            let columns = [GridItem(.adaptive(minimum: 160), spacing: 25, alignment: .top)]
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                                ForEach(allWebResults) { result in
                                    MediaThumbnailView(result: result, isLocal: false) {
                                        addMedia(result)
                                    }
                                    .id("web_\(result.id)")
                                }
                            }
                            .padding(.horizontal, 30)
                        }
                    } else if !isSearching && !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
                .padding(.vertical, 30)
            }
        }
        .background(Color.clear)
        .onChange(of: searchText) { oldValue, newValue in
            searchTask?.cancel()
            if newValue.isEmpty {
                movieResults = []
                tvResults = []
            } else {
                searchTask = Task { await performSearch() }
            }
        }
        .alert("Search Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .onAppear {
            if !searchText.isEmpty {
                searchTask = Task { await performSearch() }
            }
        }
    }

    @ViewBuilder
    private func webSection(title: String, icon: String, items: [MediaSearchResult]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.title3.bold())
                }
                .padding(.horizontal, 30)

                let columns = [GridItem(.adaptive(minimum: 160), spacing: 25, alignment: .top)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 30) {
                    ForEach(items) { result in
                        MediaThumbnailView(result: result, isLocal: false) {
                            addMedia(result)
                        }
                        .id("trending_\(result.id)")
                    }
                }
                .padding(.horizontal, 30)
            }
        }
    }

    private func filterExisting(_ results: [MediaSearchResult]) -> [MediaSearchResult] {
        let lookup = Set(existingItems.map { "\($0.id)_\($0.type?.rawValue ?? "")" })
        return results.filter { !lookup.contains("\($0.id)_\($0.type.rawValue)") }
    }

    private func performSearch() async {
        guard !SleepManager.shared.isAsleep else { return }
        guard !searchText.isEmpty else {
            movieResults = []
            tvResults = []
            isOfflineResultsOnly = false
            return
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        
        isSearching = true
        isOfflineResultsOnly = false
        
        let currentSearch = searchText

        do {
            var movies: [MediaSearchResult] = []
            var tv: [MediaSearchResult] = []

            if selectedType == .all || selectedType == .movie {
                movies = try await APIClient.shared.searchMovies(query: currentSearch)
            }

            if selectedType == .all || selectedType == .tvShow {
                tv = try await APIClient.shared.searchTVShows(query: currentSearch)
            }

            if Task.isCancelled { return }

            await MainActor.run {
                self.movieResults = movies
                self.tvResults = tv
                self.isSearching = false
                self.isOfflineResultsOnly = false
                withAnimation {
                    self.resultsCount += 1
                }
            }
        } catch {
            await MainActor.run {
                self.isSearching = false
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain || (error is URLError) {
                    self.isOfflineResultsOnly = true
                } else if self.filteredLocalResults.isEmpty {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

    @MainActor
    private func addMedia(_ result: MediaSearchResult) {
        let typePrefix = result.type == .movie ? "movie" : "tv"
        let uniqueID = "\(typePrefix)_\(result.id)"

        // Prevent race condition (double-click)
        if DataService.shared.isProcessing(id: uniqueID) { return }
        DataService.shared.startProcessing(id: uniqueID)

        Task {
            defer { DataService.shared.stopProcessing(id: uniqueID) }

            // Uniqueness Check
            let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate<MediaItem> { $0.id == uniqueID })
            if let existing = try? modelContext.fetch(descriptor).first {
                await MainActor.run {
                    AppErrorState.shared.surfaceError("Title already in Library", systemImage: "info.circle.fill")
                    isSearchActive = false
                    onSelectLocal?(existing)
                }
                return
            }

            let releaseDate = result.releaseDate != nil ? DateUtils.parseDate(result.releaseDate) : nil
            let item = MediaItem(
                id: uniqueID, title: result.title, overview: result.overview,
                posterURL: result.posterURL, releaseDate: releaseDate, type: result.type)
            item.dateAdded = Date()

            if result.type == .movie, let tmdbID = Int(result.id) {
                let details = try? await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                if let details = details {
                    item.releaseDate = DateUtils.parseDate(details.releaseDate)
                    
                    // High-res upgrades on initial add
                    if let poster = details.posterPath {
                        item.posterURL = "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(poster)"
                    }
                    if let backdrop = details.backdropPath {
                        item.backdropURL = "https://image.tmdb.org/t/p/w780\(backdrop)"
                    }

                    let movieDetails = MovieDetails(tmdbID: tmdbID)
                    movieDetails.item = item
                    movieDetails.runtime = details.runtime
                    movieDetails.genres = details.genres
                    movieDetails.voteAverage = details.voteAverage
                    movieDetails.originalLanguage = details.originalLanguage
                    movieDetails.creators = details.directors.map { $0.name }
                    
                    movieDetails.cast = details.cast.map { c in
                        let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                        let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                        member.movieDetails = movieDetails
                        return member
                    }
                    item.movieDetails = movieDetails
                }
            } else if result.type == .tvShow, let tmdbID = Int(result.id) {
                let details = try? await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
                if let details = details {
                    // High-res upgrades on initial add
                    if let poster = details.posterPath {
                        item.posterURL = "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(poster)"
                    }
                    if let backdrop = details.backdropPath {
                        item.backdropURL = "https://image.tmdb.org/t/p/w780\(backdrop)"
                    }

                    let tvDetails = TVShowDetails(tmdbID: tmdbID)
                    tvDetails.status = details.status
                    tvDetails.network = details.network
                    tvDetails.networkLogoPath = details.networkLogoPath
                    tvDetails.originalLanguage = details.originalLanguage
                    tvDetails.numberOfSeasons = details.seasonsCount
                    tvDetails.numberOfEpisodes = details.episodesCount
                    tvDetails.voteAverage = details.voteAverage
                    tvDetails.genres = details.genres
                    tvDetails.creators = details.creators.map { $0.name }
                    tvDetails.item = item
                    
                    tvDetails.cast = details.cast.map { c in
                        let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                        let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                        member.tvShowDetails = tvDetails
                        return member
                    }
                    
                    tvDetails.seasons = details.seasons.map { season in
                        TVSeason(
                            seasonNumber: season.season_number, name: season.name,
                            episodeCount: season.episode_count, airDate: season.air_date,
                            showID: tmdbID)
                    }
                    tvDetails.tvMazeID = details.tvdbID
                    item.tvShowDetails = tvDetails
                    
                    // Trigger immediate background sync for episodes
                    DataService.shared.refreshMetadata(for: [item], modelContext: modelContext)
                }
            }

            item.updateSearchableText()
            modelContext.insert(item)
            try? modelContext.save()
            
            // Navigate to the newly added item's detail view
            await MainActor.run {
                isSearchActive = false
                onSelectLocal?(item)
            }
        }
    }
}
