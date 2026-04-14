import Foundation

enum APIError: Error, LocalizedError {
    case missingApiKey(String)
    case invalidResponse
    case requestFailed(Int)
    
    var errorDescription: String? {
        switch self {
        case .missingApiKey(let service): return "\(service) API Key is missing. Please check Settings."
        case .invalidResponse: return "Received an invalid response from the server."
        case .requestFailed(let code): return "Request failed with status code: \(code)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()
    private let decoder = JSONDecoder()
    
    private var tmdbApiKey: String { UserDefaults.standard.string(forKey: "tmdb_api_key") ?? "" }
    private var googleBooksApiKey: String { UserDefaults.standard.string(forKey: "google_books_api_key") ?? "" }
    
    nonisolated var isTMDBConfigured: Bool { 
        UserDefaults.standard.string(forKey: "tmdb_api_key")?.isEmpty == false 
    }
    nonisolated var isGoogleBooksConfigured: Bool { 
        UserDefaults.standard.string(forKey: "google_books_api_key")?.isEmpty == false 
    }
    
    private func tmdbURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let key = tmdbApiKey
        guard !key.isEmpty else { throw APIError.missingApiKey("TMDB") }
        var components = URLComponents(string: "https://api.themoviedb.org/3\(path)")
        var items = [URLQueryItem(name: "api_key", value: key)]
        items.append(contentsOf: queryItems)
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    // MARK: - Generic Search
    private func searchTMDB<T: Codable & TMDBMedia>(path: String, query: String) async throws -> [T] {
        let url = try tmdbURL(path: path, queryItems: [URLQueryItem(name: "query", value: query)])
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let decoded = try decoder.decode(TMDBGenericResponse<T>.self, from: data)
        return decoded.results
    }

    func searchMovies(query: String) async throws -> [MovieSearchResult] {
        let results: [TMDBMovie] = try await searchTMDB(path: "/search/movie", query: query)
        return results.map { $0.toSearchResult() }
    }
    
    func searchTVShows(query: String) async throws -> [TVSearchResult] {
        let results: [TMDBTV] = try await searchTMDB(path: "/search/tv", query: query)
        return results.map { $0.toSearchResult() }
    }
    
    func fetchTrendingMovies() async throws -> [MovieSearchResult] {
        let url = try tmdbURL(path: "/trending/movie/day")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let decoded = try decoder.decode(TMDBGenericResponse<TMDBMovie>.self, from: data)
        return decoded.results.prefix(10).map { $0.toSearchResult() }
    }
    
    func fetchTrendingTVShows() async throws -> [TVSearchResult] {
        let url = try tmdbURL(path: "/trending/tv/day")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let decoded = try decoder.decode(TMDBGenericResponse<TMDBTV>.self, from: data)
        return decoded.results.prefix(10).map { $0.toSearchResult() }
    }

    // MARK: - Details
    func fetchMovieDetails(tmdbID: Int) async throws -> (runtime: Int?, genres: [String], voteAverage: Double?, releaseDate: String?, cast: [CastMemberResult]) {
        let url = try tmdbURL(path: "/movie/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: "credits")])
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let details = try decoder.decode(TMDBMovieDetailsResponse.self, from: data)
        let cast = details.credits?.cast.prefix(15).map { 
            CastMemberResult(name: $0.name, character: $0.character, profilePath: $0.profile_path, order: $0.order)
        } ?? []
        return (details.runtime, details.genres.map { $0.name }, details.vote_average, details.release_date, Array(cast))
    }
    
    func fetchTVDetails(tmdbID: Int) async throws -> (seasonsCount: Int, episodesCount: Int, status: String, voteAverage: Double?, seasons: [TMDBSeasonBrief], firstAirDate: String?, nextEpisodeDate: String?, nextEpisodeNumber: Int?, nextSeasonNumber: Int?, tvdbID: Int?, cast: [CastMemberResult]) {
        let url = try tmdbURL(path: "/tv/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: "external_ids,credits")])
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let d = try decoder.decode(TMDBTVDetailsResponse.self, from: data)
        let cast = d.credits?.cast.prefix(15).map { 
            CastMemberResult(name: $0.name, character: $0.character, profilePath: $0.profile_path, order: $0.order)
        } ?? []
        return (d.number_of_seasons, d.number_of_episodes, d.status, d.vote_average, d.seasons ?? [], d.first_air_date, d.next_episode_to_air?.air_date, d.next_episode_to_air?.episode_number, d.next_episode_to_air?.season_number, d.external_ids?.tvdb_id, Array(cast))
    }

    func fetchSeasonDetails(tmdbID: Int, seasonNumber: Int) async throws -> [TVEpisodeResult] {
        let url = try tmdbURL(path: "/tv/\(tmdbID)/season/\(seasonNumber)")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let decoded = try decoder.decode(TMDBSeasonResponse.self, from: data)
        return decoded.episodes.map { 
            TVEpisodeResult(episodeNumber: $0.episode_number, name: $0.name, overview: $0.overview, airDate: $0.air_date, runtime: $0.runtime)
        }
    }

    // MARK: - Book Search
    func searchBooks(query: String) async throws -> [BookSearchResult] {
        let components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        let key = googleBooksApiKey
        var items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "maxResults", value: "20")]
        if !key.isEmpty { items.append(URLQueryItem(name: "key", value: key)) }
        guard let url = components?.url?.appending(queryItems: items) else { throw URLError(.badURL) }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let responseObj = try decoder.decode(GoogleBooksResponse.self, from: data)
        return responseObj.items?.compactMap { item in
            let info = item.volumeInfo
            let coverURL = info.imageLinks?.thumbnail?
                .replacingOccurrences(of: "http://", with: "https://")
                .replacingOccurrences(of: "&zoom=1", with: "&zoom=2")
            return BookSearchResult(id: item.id, title: info.title ?? "Unknown", authors: info.authors ?? ["Unknown"], overview: info.description ?? "", coverURL: coverURL, pageCount: info.pageCount)
        } ?? []
    }

    // MARK: - TVMaze Integration
    func lookupTVMazeID(tvdbID: Int) async throws -> Int? {
        var components = URLComponents(string: "https://api.tvmaze.com/lookup/shows")
        components?.queryItems = [URLQueryItem(name: "thetvdb", value: String(tvdbID))]
        guard let url = components?.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode == 200 {
            let show = try decoder.decode(TVMazeShowLookupResponse.self, from: data)
            return show.id
        }
        return nil
    }

    func fetchTVMazeSchedule(tvMazeID: Int) async throws -> (episode: TVMazeEpisode?, timezone: String?, serviceName: String?) {
        let url = URL(string: "https://api.tvmaze.com/shows/\(tvMazeID)?embed=nextepisode")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let r = try decoder.decode(TVMazeResponse.self, from: data)
        return (r._embedded?.nextepisode, r.timezone, r.webChannel?.name ?? r.network?.name)
    }

    func fetchTVMazeEpisodes(tvMazeID: Int) async throws -> [TVMazeEpisode] {
        let url = URL(string: "https://api.tvmaze.com/shows/\(tvMazeID)/episodes")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        return try decoder.decode([TVMazeEpisode].self, from: data)
    }

    
    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if !(200...299).contains(http.statusCode) { throw APIError.requestFailed(http.statusCode) }
    }
}

// MARK: - Models
protocol TMDBMedia {
    var id: Int { get }
    var overview: String { get }
    var poster_path: String? { get }
}

struct TMDBGenericResponse<T: Codable>: Codable {
    let results: [T]
}

struct TMDBMovie: Codable, TMDBMedia {
    let id: Int
    let title: String
    let overview: String
    let poster_path: String?
    let release_date: String?
    let genre_ids: [Int]?
    
    func toSearchResult() -> MovieSearchResult {
        let genres = genre_ids?.compactMap { TMDBGenreMap.movieGenres[$0] }.prefix(2) ?? []
        return MovieSearchResult(id: String(id), title: title, overview: overview, posterURL: "https://image.tmdb.org/t/p/w780\(poster_path ?? "")", releaseDate: release_date, genres: Array(genres))
    }
}

struct TMDBTV: Codable, TMDBMedia {
    let id: Int
    let name: String
    let overview: String
    let poster_path: String?
    let first_air_date: String?
    let genre_ids: [Int]?
    
    func toSearchResult() -> TVSearchResult {
        let genres = genre_ids?.compactMap { TMDBGenreMap.tvGenres[$0] }.prefix(2) ?? []
        return TVSearchResult(id: String(id), title: name, overview: overview, posterURL: "https://image.tmdb.org/t/p/w780\(poster_path ?? "")", releaseDate: first_air_date, genres: Array(genres))
    }
}

struct TMDBGenreMap {
    static let movieGenres: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History", 
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Sci-Fi", 
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western"
    ]
    static let tvGenres: [Int: String] = [
        10759: "Action & Adventure", 16: "Animation", 35: "Comedy", 80: "Crime", 
        99: "Documentary", 18: "Drama", 10751: "Family", 10762: "Kids", 9648: "Mystery", 
        10763: "News", 10764: "Reality", 10765: "Sci-Fi & Fantasy", 10766: "Soap", 
        10767: "Talk", 10768: "War & Politics", 37: "Western"
    ]
}

struct TMDBMovieDetailsResponse: Codable {
    let runtime: Int?, genres: [TMDBGenre], vote_average: Double?, release_date: String?, credits: TMDBCreditsResponse?
}

struct TMDBTVDetailsResponse: Codable {
    let number_of_seasons: Int, number_of_episodes: Int, status: String, vote_average: Double?
    let seasons: [TMDBSeasonBrief]?, first_air_date: String?, next_episode_to_air: TMDBNextEpisode?, external_ids: TMDBExternalIDs?, credits: TMDBCreditsResponse?
}

struct TMDBCreditsResponse: Codable {
    let cast: [TMDBMovieCastMember]
}

struct TMDBMovieCastMember: Codable {
    let name: String
    let character: String
    let profile_path: String?
    let order: Int
}

struct CastMemberResult: Codable {
    let name: String
    let character: String
    let profilePath: String?
    let order: Int
}

struct TMDBExternalIDs: Codable { let tvdb_id: Int? }
struct TMDBNextEpisode: Codable { let air_date: String?, episode_number: Int?, season_number: Int? }
struct TMDBSeasonBrief: Codable { let season_number: Int, name: String, episode_count: Int, air_date: String? }
struct TMDBSeasonResponse: Codable { let episodes: [TMDBEpisodeBrief] }
struct TMDBEpisodeBrief: Codable { let episode_number: Int, name: String, overview: String, air_date: String?, runtime: Int? }
struct TMDBGenre: Codable { let name: String }

struct GoogleBooksResponse: Codable { let items: [GoogleBookItem]? }
struct GoogleBookItem: Codable { let id: String, volumeInfo: GoogleVolumeInfo }
struct GoogleVolumeInfo: Codable { let title: String?, authors: [String]?, description: String?, imageLinks: GoogleImageLinks?, pageCount: Int? }
struct GoogleImageLinks: Codable { let thumbnail: String? }

struct TVMazeShowLookupResponse: Codable { let id: Int }
struct TVMazeResponse: Codable {
    let _embedded: TVMazeEmbedded?, network: TVMazeNetwork?, webChannel: TVMazeWebChannel?
    var timezone: String? { network?.country?.timezone ?? webChannel?.country?.timezone }
}
struct TVMazeNetwork: Codable { let name: String?, country: TVMazeCountry? }
struct TVMazeWebChannel: Codable { let name: String?, country: TVMazeCountry? }
struct TVMazeCountry: Codable { let timezone: String? }
struct TVMazeEmbedded: Codable { let nextepisode: TVMazeEpisode? }
struct TVMazeEpisode: Codable { let season: Int?, number: Int?, name: String, airdate: String, airtime: String, airstamp: String? }

struct MovieSearchResult: Identifiable { let id: String, title: String, overview: String, posterURL: String?, releaseDate: String?, genres: [String] }
struct TVSearchResult: Identifiable { let id: String, title: String, overview: String, posterURL: String?, releaseDate: String?, genres: [String] }
struct BookSearchResult: Identifiable { let id: String, title: String, authors: [String], overview: String, coverURL: String?, pageCount: Int? }
struct TVEpisodeResult: Codable { let episodeNumber: Int, name: String, overview: String, airDate: String?, runtime: Int? }
