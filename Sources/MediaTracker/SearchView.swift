import SwiftUI
import SwiftData

enum SearchType: String, CaseIterable {
    case all = "All"
    case movie = "Movies"
    case tvShow = "TV Shows"
    case book = "Books"
}

enum AnySearchResult: Identifiable {
    case movie(MovieSearchResult)
    case tv(TVSearchResult)
    case book(BookSearchResult)
    
    var id: String {
        switch self {
        case .movie(let m): return "movie-\(m.id)"
        case .tv(let t): return "tv-\(t.id)"
        case .book(let b): return "book-\(b.id)"
        }
    }
}

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var existingItems: [MediaItem]
    
    @Binding var searchText: String
    @Binding var isSearchActive: Bool
    @State private var selectedType: SearchType = .all
    @State private var resultsCount = 0 // Used to trigger staggered animations
    
    @State private var movieResults: [MovieSearchResult] = []
    @State private var tvResults: [TVSearchResult] = []
    @State private var bookResults: [BookSearchResult] = []
    
    @State private var trendingMovies: [MovieSearchResult] = []
    @State private var trendingTV: [TVSearchResult] = []
    
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var onSelectLocal: ((MediaItem) -> Void)?
    
    private var allWebResults: [AnySearchResult] {
        var results: [AnySearchResult] = []
        if selectedType == .all || selectedType == .movie {
            let filtered = movieResults.filter { !isAdded(id: $0.id, type: .movie) }
            results.append(contentsOf: filtered.prefix(6).map { .movie($0) })
        }
        if selectedType == .all || selectedType == .tvShow {
            let filtered = tvResults.filter { !isAdded(id: $0.id, type: .tvShow) }
            results.append(contentsOf: filtered.prefix(6).map { .tv($0) })
        }
        if selectedType == .all || selectedType == .book {
            let filtered = bookResults.filter { !isAdded(id: $0.id, type: .book) }
            results.append(contentsOf: filtered.prefix(6).map { .book($0) })
        }
        return results
    }
    
    init(searchText: Binding<String>, isSearchActive: Binding<Bool>, initialType: MediaType? = nil, onSelectLocal: ((MediaItem) -> Void)? = nil) {
        self._searchText = searchText
        self._isSearchActive = isSearchActive
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
                            Text("In Your Library")
                                .font(.title2.bold())
                                .padding(.horizontal, 20)
                            
                            let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(localResults) { item in
                                    Button {
                                        isSearchActive = false
                                        onSelectLocal?(item)
                                    } label: {
                                        UnifiedResultCard(
                                            title: item.title,
                                            category: item.type?.rawValue ?? "Media",
                                            year: item.releaseDate?.formatted(.dateTime.year()),
                                            genres: [],
                                            posterURL: item.posterURL,
                                            isAdded: true,
                                            isLocal: true
                                        ) {}
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        Divider().padding(.horizontal, 20)
                    }
                    
                    if searchText.isEmpty {
                        VStack(spacing: 0) {
                            if selectedType == .all || selectedType == .movie {
                                let items = trendingMovies.filter { !isAdded(id: $0.id, type: .movie) }.map { AnySearchResult.movie($0) }
                                webSection(title: "Trending Movies", items: items)
                            }
                            if selectedType == .all || selectedType == .tvShow {
                                let items = trendingTV.filter { !isAdded(id: $0.id, type: .tvShow) }.map { AnySearchResult.tv($0) }
                                webSection(title: "Trending TV Shows", items: items)
                            }
                        }
                    } else if !allWebResults.isEmpty {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("From the Web")
                                .font(.title2.bold())
                                .padding(.horizontal, 20)
                            
                            let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                                ForEach(allWebResults) { result in
                                    Group {
                                        switch result {
                                        case .movie(let movie):
                                            let year = movie.releaseDate?.prefix(4).description ?? "TBA"
                                            UnifiedResultCard(
                                                title: movie.title,
                                                category: "Movie",
                                                year: year,
                                                genres: movie.genres,
                                                posterURL: movie.posterURL,
                                                isAdded: false
                                            ) {
                                                addMovie(movie)
                                            }
                                        case .tv(let tv):
                                            let year = tv.releaseDate?.prefix(4).description ?? "TBA"
                                            UnifiedResultCard(
                                                title: tv.title,
                                                category: "TV Show",
                                                year: year,
                                                genres: tv.genres,
                                                posterURL: tv.posterURL,
                                                isAdded: false
                                            ) {
                                                addTVShow(tv)
                                            }
                                        case .book(let book):
                                            UnifiedResultCard(
                                                title: book.title,
                                                category: "Book",
                                                year: nil,
                                                genres: book.authors,
                                                posterURL: book.coverURL,
                                                isAdded: false
                                            ) {
                                                addBook(book)
                                            }
                                        }
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
        .task(id: searchText) {
            if !searchText.isEmpty {
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    await performSearch()
                } catch {
                    // Task cancelled implicitly handled
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
        .onAppear {
            loadTrending()
        }
    }
    
    @ViewBuilder
    private func webSection(title: String, items: [AnySearchResult]) -> some View {
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
                        Group {
                            switch result {
                            case .movie(let movie):
                                let year = movie.releaseDate?.prefix(4).description ?? "TBA"
                                UnifiedResultCard(
                                    title: movie.title,
                                    category: "Movie",
                                    year: year,
                                    genres: movie.genres,
                                    posterURL: movie.posterURL,
                                    isAdded: false
                                ) {
                                    addMovie(movie)
                                }
                            case .tv(let tv):
                                let year = tv.releaseDate?.prefix(4).description ?? "TBA"
                                UnifiedResultCard(
                                    title: tv.title,
                                    category: "TV Show",
                                    year: year,
                                    genres: tv.genres,
                                    posterURL: tv.posterURL,
                                    isAdded: false
                                ) {
                                    addTVShow(tv)
                                }
                            case .book(let book):
                                UnifiedResultCard(
                                    title: book.title,
                                    category: "Book",
                                    year: nil,
                                    genres: book.authors,
                                    posterURL: book.coverURL,
                                    isAdded: false
                                ) {
                                    addBook(book)
                                }
                            }
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
    private func addMovie(_ movie: MovieSearchResult) {
        Task {
            let releaseDate = DateUtils.parseDate(movie.releaseDate)
            let item = MediaItem(id: movie.id, title: movie.title, overview: movie.overview, posterURL: movie.posterURL, releaseDate: releaseDate, type: .movie)
            if let tmdbID = Int(movie.id) {
                let details = try? await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                item.movieDetails = MovieDetails(tmdbID: tmdbID, runtime: details?.runtime, genres: details?.genres ?? [], voteAverage: details?.voteAverage)
            }
            modelContext.insert(item)
            SpotlightManager.shared.indexItem(item)
            isSearchActive = false
            onSelectLocal?(item)
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
            SpotlightManager.shared.indexItem(item)
            isSearchActive = false
            onSelectLocal?(item)
        }
    }
    
    @MainActor
    private func addBook(_ book: BookSearchResult) {
        let item = MediaItem(id: book.id, title: book.title, overview: book.overview, posterURL: book.coverURL, type: .book)
        item.bookDetails = BookDetails(googleBooksID: book.id, authors: book.authors, pageCount: book.pageCount)
        modelContext.insert(item)
        SpotlightManager.shared.indexItem(item)
        isSearchActive = false
        onSelectLocal?(item)
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
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottom) {
                    // Poster with fixed size
                    Group {
                        if let urlString = posterURL, let url = URL(string: urlString) {
                            CachedImage(url: url, targetSize: CGSize(width: 480, height: 720)) {
                                placeholderIcon
                            }
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 160, height: 240)
                        } else {
                            placeholderIcon
                        }
                    }
                    .frame(width: 160, height: 240)
                    .clipped()
                    .cornerRadius(12)
                    .shadow(color: isHovering && !isAdded ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.1), radius: isHovering ? 12 : 4)
                    .scaleEffect(isHovering && !isAdded ? 1.02 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
                    
                    // "In Library" Overlay
                    if isAdded {
                        ZStack {
                            Rectangle()
                                .fill(.black.opacity(isLocal ? 0.1 : 0.6))
                                .frame(width: 160, height: 240)
                                .cornerRadius(12)
                            
                            if !isLocal {
                                VStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.green)
                                    Text("In Library")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            } else {
                                // Subtle badge for local items
                                VStack {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "folder.fill")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.white)
                                            .padding(6)
                                            .background(.ultraThinMaterial)
                                            .clipShape(Circle())
                                            .padding(8)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    } else if isHovering {
                        // Hover Overlay
                        ZStack {
                            Rectangle()
                                .fill(.black.opacity(0.3))
                                .frame(width: 160, height: 240)
                                .cornerRadius(12)
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.white)
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: 160, height: 240)
                
                // Text Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 40, alignment: .topLeading)
                        .foregroundStyle(isAdded && !isLocal ? .secondary : .primary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(category)
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isAdded && !isLocal ? Color.secondary.opacity(0.1) : Color.accentColor.opacity(0.15))
                                .foregroundStyle(isAdded && !isLocal ? .secondary : Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            
                            if let year = year {
                                Text(year)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        if !genres.isEmpty {
                            Text(genres.joined(separator: " • "))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(width: 160)
            }
            .frame(width: 160)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded && !isLocal)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
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
