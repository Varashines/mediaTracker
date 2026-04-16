import SwiftData
import SwiftUI

enum SearchType: String, CaseIterable {
    case all = "All"
    case movie = "Movies"
    case tvShow = "TV Shows"
    case book = "Books"
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
    @State private var bookResults: [MediaSearchResult] = []

    @State private var trendingMovies: [MediaSearchResult] = []
    @State private var trendingTV: [MediaSearchResult] = []

    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showError = false

    var onSelectLocal: ((MediaItem) -> Void)?

    private var allWebResults: [MediaSearchResult] {
        var results: [MediaSearchResult] = []
        if selectedType == .all || selectedType == .movie {
            results.append(
                contentsOf: movieResults.filter { !isAdded(id: $0.id, type: .movie) }.prefix(10))
        }
        if selectedType == .all || selectedType == .tvShow {
            results.append(
                contentsOf: tvResults.filter { !isAdded(id: $0.id, type: .tvShow) }.prefix(10))
        }
        if selectedType == .all || selectedType == .book {
            results.append(
                contentsOf: bookResults.filter { !isAdded(id: $0.id, type: .book) }.prefix(10))
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
            case .book: searchType = .book
            }
            _selectedType = State(initialValue: searchType)
        } else {
            _selectedType = State(initialValue: .all)
        }
    }

    private var localResults: [MediaItem] {
        guard !searchText.isEmpty else { return [] }
        var items = existingItems.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        if selectedType != .all {
            let filterType: MediaType? = {
                switch selectedType {
                case .movie: return .movie
                case .tvShow: return .tvShow
                case .book: return .book
                default: return nil
                }
            }()

            if let type = filterType {
                items = items.filter { $0.type == type }
            }
        }
        return items
    }

    private func isAdded(id: String, type: MediaType) -> Bool {
        return existingItems.contains { $0.id == id && $0.type == type }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Media Type", selection: $selectedType) {
                ForEach(SearchType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()

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
                                    UnifiedResultCard(
                                        title: item.title,
                                        category: item.type?.rawValue ?? "Media",
                                        year: item.releaseDate?.formatted(.dateTime.year()),
                                        genres: item.genres,
                                        posterURL: item.posterURL,
                                        isAdded: true,
                                        isLocal: true
                                    ) {
                                        // Improvement: Clear search focus when navigating to library item
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
                        VStack(spacing: 0) {
                            if selectedType == .all || selectedType == .movie {
                                let items = trendingMovies.filter {
                                    !isAdded(id: $0.id, type: .movie)
                                }
                                webSection(title: "Trending Movies", items: items)
                            }
                            if selectedType == .all || selectedType == .tvShow {
                                let items = trendingTV.filter { !isAdded(id: $0.id, type: .tvShow) }
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
                                    UnifiedResultCard(result: result, isAdded: false) {
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
            if newValue.isEmpty {
                movieResults = []
                tvResults = []
                bookResults = []
                loadTrending()
            }
        }
        .onChange(of: submitTrigger) { oldValue, newValue in
            Task { await performSearch() }
        }
        .onChange(of: selectedType) { oldValue, newValue in
            Task { await performSearch() }
        }
        .alert("Search Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .onAppear {
            loadTrending()
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
                        UnifiedResultCard(result: result, isAdded: false) {
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
        guard !searchText.isEmpty else {
            movieResults = []
            tvResults = []
            bookResults = []
            return
        }
        isSearching = true

        do {
            var movies: [MediaSearchResult] = []
            var tv: [MediaSearchResult] = []
            var books: [MediaSearchResult] = []

            if selectedType == .all || selectedType == .movie {
                movies = try await APIClient.shared.searchMovies(query: searchText)
            }

            if selectedType == .all || selectedType == .tvShow {
                tv = try await APIClient.shared.searchTVShows(query: searchText)
            }

            if selectedType == .all || selectedType == .book {
                books = try await APIClient.shared.searchBooks(query: searchText)
            }

            let finalMovies = movies
            let finalTV = tv
            let finalBooks = books

            await MainActor.run {
                self.movieResults = finalMovies
                self.tvResults = finalTV
                self.bookResults = finalBooks
                self.isSearching = false
                withAnimation {
                    self.resultsCount += 1
                }
            }
        } catch {
            if error is CancellationError || (error as NSError).code == NSURLErrorCancelled {
                await MainActor.run { self.isSearching = false }
                return
            }
            let message = error.localizedDescription
            await MainActor.run {
                self.errorMessage = message
                self.showError = true
                self.isSearching = false
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

            if result.type == .movie, let tmdbID = Int(result.id) {
                let details = try? await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                if let details = details {
                    item.releaseDate = DateUtils.parseDate(details.releaseDate)
                    item.movieDetails = MovieDetails(
                        tmdbID: tmdbID, runtime: details.runtime, genres: details.genres,
                        voteAverage: details.voteAverage)
                }
            } else if result.type == .tvShow, let tmdbID = Int(result.id) {
                let details = try? await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
                if let details = details {
                    let tvDetails = TVShowDetails(
                        tmdbID: tmdbID,
                        status: details.status,
                        numberOfSeasons: details.seasonsCount,
                        numberOfEpisodes: details.episodesCount,
                        voteAverage: details.voteAverage
                    )
                    tvDetails.seasons = details.seasons.map { season in
                        TVSeason(
                            seasonNumber: season.season_number, name: season.name,
                            episodeCount: season.episode_count, airDate: season.air_date)
                    }
                    tvDetails.tvdbID = details.tvdbID
                    item.tvShowDetails = tvDetails
                }
            } else if result.type == .book {
                // For books, we don't have a separate details fetch yet in this simplified flow
                // but we can initialize BookDetails from the search result if needed.
                item.bookDetails = BookDetails(googleBooksID: result.id, authors: result.genres)
            }

            modelContext.insert(item)
            SpotlightManager.shared.indexItem(item)
            onSelectLocal?(item)
        }
    }
}

struct UnifiedResultCard: View {
    let title: String
    let category: String
    let year: String?
    let genres: [String]
    let posterURL: String?
    let isAdded: Bool
    var isLocal: Bool = false
    let action: () -> Void

    init(result: MediaSearchResult, isAdded: Bool, action: @escaping () -> Void) {
        self.title = result.title
        self.category = result.type.rawValue
        self.year = result.releaseDate?.prefix(4).description
        self.genres = result.genres
        self.posterURL = result.posterURL
        self.isAdded = isAdded
        self.isLocal = false
        self.action = action
    }

    init(
        title: String, category: String, year: String?, genres: [String], posterURL: String?,
        isAdded: Bool, isLocal: Bool, action: @escaping () -> Void
    ) {
        self.title = title
        self.category = category
        self.year = year
        self.genres = genres
        self.posterURL = posterURL
        self.isAdded = isAdded
        self.isLocal = isLocal
        self.action = action
    }

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .top) {
                    // 1. Poster Layer
                    Group {
                        if let urlString = posterURL, let url = URL(string: urlString) {
                            CachedImage(url: url, targetSize: CGSize(width: 160, height: 240)) { _ in
                            } placeholder: {
                                placeholderIcon
                            }
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 160, height: 240)
                            .clipped()
                        } else {
                            placeholderIcon
                                .frame(width: 160, height: 240)
                        }
                    }
                    
                    // 2. Hover/Status Overlay
                    if isAdded {
                        ZStack {
                            Rectangle()
                                .fill(.black.opacity(isLocal ? (isHovering ? 0.2 : 0.05) : 0.6))
                            
                            if !isLocal {
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.green)
                                    Text("In Library")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            } else if isHovering {
                                VStack(spacing: 4) {
                                    Image(systemName: "arrow.up.right.circle.fill")
                                        .font(.system(size: 30))
                                        .foregroundStyle(.white)
                                    Text("Open")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                }
                                .padding(8)
                                .background(.black.opacity(0.4))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    } else if isHovering {
                        ZStack {
                            Rectangle().fill(.black.opacity(0.3))
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white)
                        }
                    }
                    
                    // 3. Top Pills
                    topPills
                }
                .frame(width: 160, height: 240)
                .cornerRadius(12)
                .scaleEffect(isHovering ? 1.02 : 1.0)
                .animation(.easeOut(duration: 0.2), value: isHovering)
                
                // 4. Info Section (Below)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 34, alignment: .topLeading)
                    
                    if let year = year {
                        Text(year)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                            .liquidGlassPill(accentColor: .primary, isSolid: false)
                    }
                }
                .padding(.horizontal, 2)
            }
            .frame(width: 160)
            .contentShape(Rectangle())
            .drawingGroup()
        }
        .buttonStyle(.plain)
        .disabled(isAdded && !isLocal)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    @ViewBuilder
    private var topPills: some View {
        HStack(alignment: .top) {
            categoryPill
            Spacer()
            statusPill
        }
        .padding(6)
    }

    @ViewBuilder
    private var categoryPill: some View {
        Image(systemName: iconName)
            .font(.system(size: 9, weight: .bold))
            .liquidGlassPill(accentColor: .accentColor, isSolid: false)
    }

    @ViewBuilder
    private var statusPill: some View {
        if isAdded {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .liquidGlassPill(accentColor: .green, isSolid: true)
        }
    }

    private var placeholderIcon: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.1))
            .overlay {
                Image(systemName: iconName)
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
    }

    private var iconName: String {
        if category.contains("Movie") { return "film" }
        if category.contains("TV Show") { return "tv" }
        return "book"
    }
}
