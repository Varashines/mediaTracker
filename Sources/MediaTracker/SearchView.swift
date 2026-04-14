import SwiftUI
import SwiftData

enum SearchType: String, CaseIterable {
    case all = "All"
    case movie = "Movies"
    case tvShow = "TV Shows"
    case book = "Books"
}

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingItems: [MediaItem]
    
    @State private var searchText = ""
    @State private var selectedType: SearchType = .all
    
    @State private var movieResults: [MovieSearchResult] = []
    @State private var tvResults: [TVSearchResult] = []
    @State private var bookResults: [BookSearchResult] = []
    
    @State private var trendingMovies: [MovieSearchResult] = []
    @State private var trendingTV: [TVSearchResult] = []
    
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    init(initialType: MediaType? = nil) {
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
    
    private func isAdded(id: String, type: MediaType) -> Bool {
        return existingItems.contains { $0.id == id && $0.type == type }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Media Type", selection: $selectedType) {
                    ForEach(SearchType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                List {
                    if searchText.isEmpty {
                        Section("Trending & Suggestions") {
                            if selectedType == .all || selectedType == .movie {
                                ForEach(trendingMovies) { movie in
                                    SearchResultRow(title: movie.title, subtitle: "Trending Movie", posterURL: movie.posterURL, isAdded: isAdded(id: movie.id, type: .movie)) {
                                        addMovie(movie)
                                    }
                                }
                            }
                            if selectedType == .all || selectedType == .tvShow {
                                ForEach(trendingTV) { tv in
                                    SearchResultRow(title: tv.title, subtitle: "Trending TV Show", posterURL: tv.posterURL, isAdded: isAdded(id: tv.id, type: .tvShow)) {
                                        addTVShow(tv)
                                    }
                                }
                            }
                        }
                    } else {
                        if selectedType == .all || selectedType == .movie {
                            Section("Movies") {
                                ForEach(movieResults) { movie in
                                    SearchResultRow(title: movie.title, subtitle: "Movie", posterURL: movie.posterURL, isAdded: isAdded(id: movie.id, type: .movie)) {
                                        addMovie(movie)
                                    }
                                }
                            }
                        }
                        if selectedType == .all || selectedType == .tvShow {
                            Section("TV Shows") {
                                ForEach(tvResults) { tv in
                                    SearchResultRow(title: tv.title, subtitle: "TV Show", posterURL: tv.posterURL, isAdded: isAdded(id: tv.id, type: .tvShow)) {
                                        addTVShow(tv)
                                    }
                                }
                            }
                        }
                        if selectedType == .all || selectedType == .book {
                            Section("Books") {
                                ForEach(bookResults) { book in
                                    SearchResultRow(title: book.title, subtitle: book.authors.joined(separator: ", "), posterURL: book.coverURL, isAdded: isAdded(id: book.id, type: .book)) {
                                        addBook(book)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Add Media")
            .searchable(text: $searchText, placement: .toolbar, prompt: "Search movies, shows, books...")
            .task(id: searchText) {
                if !searchText.isEmpty {
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                        await performSearch()
                    } catch {
                        // Task cancelled
                    }
                } else {
                    await performSearch()
                }
            }
            .onChange(of: selectedType) { oldValue, newValue in
                Task { await performSearch() }
            }
            .alert("Search Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if isSearching {
                    ToolbarItem(placement: .status) {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .onAppear {
                loadTrending()
            }
        }
        .frame(minWidth: 500, maxWidth: 500, minHeight: 400, maxHeight: 600)
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
            var movies: [MovieSearchResult] = []
            var tv: [TVSearchResult] = []
            var books: [BookSearchResult] = []
            
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
            }
        } catch {
            let message = error.localizedDescription
            await MainActor.run {
                self.errorMessage = message
                self.showError = true
                self.isSearching = false
            }
        }
    }
    
    @MainActor
    private func addMovie(_ movie: MovieSearchResult) {
        Task {
            let releaseDate = DateUtils.parseDate(movie.releaseDate)
            let item = MediaItem(id: movie.id, title: movie.title, overview: movie.overview, posterURL: movie.posterURL, releaseDate: releaseDate, type: .movie)
            if let tmdbID = Int(movie.id) {
                let details = try? await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                item.movieDetails = MovieDetails(tmdbID: tmdbID, runtime: details?.runtime, genres: details?.genres ?? [], voteAverage: details?.voteAverage)
            }
            modelContext.insert(item)
            dismiss()
        }
    }
    
    @MainActor
    private func addTVShow(_ tv: TVSearchResult) {
        Task {
            let releaseDate = DateUtils.parseDate(tv.releaseDate)
            let item = MediaItem(id: tv.id, title: tv.title, overview: tv.overview, posterURL: tv.posterURL, releaseDate: releaseDate, type: .tvShow)
            if let tmdbID = Int(tv.id) {
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
                        TVSeason(seasonNumber: season.season_number, name: season.name, episodeCount: season.episode_count, airDate: season.air_date)
                    }
                    tvDetails.tvdbID = details.tvdbID
                    item.tvShowDetails = tvDetails
                }
            }
            modelContext.insert(item)
            dismiss()
        }
    }
    
    @MainActor
    private func addBook(_ book: BookSearchResult) {
        let item = MediaItem(id: book.id, title: book.title, overview: book.overview, posterURL: book.coverURL, type: .book)
        item.bookDetails = BookDetails(googleBooksID: book.id, authors: book.authors, pageCount: book.pageCount)
        modelContext.insert(item)
        dismiss()
    }
}

struct SearchResultRow: View {
    let title: String
    let subtitle: String
    let posterURL: String?
    let isAdded: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            if let urlString = posterURL, let url = URL(string: urlString) {
                CachedImage(url: url) {
                    Color.secondary.opacity(0.1)
                }
                .frame(width: 35, height: 50)
                .cornerRadius(4)
                .clipped()
            } else {
                Color.secondary.opacity(0.1)
                    .frame(width: 35, height: 50)
                    .cornerRadius(4)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: action) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isAdded ? .green : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
        }
        .padding(.vertical, 2)
    }
}
