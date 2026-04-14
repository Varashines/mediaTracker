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
    
    // API Keys (Synchronized with AppStorage)
    private var tmdbApiKey: String { UserDefaults.standard.string(forKey: "tmdb_api_key") ?? "" }
    private var googleBooksApiKey: String { UserDefaults.standard.string(forKey: "google_books_api_key") ?? "" }
    
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

    func searchMovies(query: String) async throws -> [MovieSearchResult] {
        let url = try tmdbURL(path: "/search/movie", queryItems: [URLQueryItem(name: "query", value: query)])
        
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        
        let decodedResponse = try decoder.decode(TMDBResponse.self, from: data)
        return decodedResponse.results.map { 
            MovieSearchResult(id: String($0.id), title: $0.title, overview: $0.overview, posterURL: "https://image.tmdb.org/t/p/w500\($0.poster_path ?? "")", releaseDate: $0.release_date)
        }
    }
    
    func searchTVShows(query: String) async throws -> [TVSearchResult] {
        let url = try tmdbURL(path: "/search/tv", queryItems: [URLQueryItem(name: "query", value: query)])
        
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        
        let decodedResponse = try decoder.decode(TMDBTVResponse.self, from: data)
        return decodedResponse.results.map { 
            TVSearchResult(id: String($0.id), title: $0.name, overview: $0.overview, posterURL: "https://image.tmdb.org/t/p/w500\($0.poster_path ?? "")", releaseDate: $0.first_air_date)
        }
    }
    
    func searchBooks(query: String) async throws -> [BookSearchResult] {
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        let key = googleBooksApiKey
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: "20")
        ]
        if !key.isEmpty {
            items.append(URLQueryItem(name: "key", value: key))
        }
        components?.queryItems = items
        
        guard let url = components?.url else { throw URLError(.badURL) }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        
        let responseObj = try decoder.decode(GoogleBooksResponse.self, from: data)
        return responseObj.items?.compactMap { item in
            let info = item.volumeInfo
            let coverURL = info.imageLinks?.thumbnail?
                .replacingOccurrences(of: "http://", with: "https://")
                .replacingOccurrences(of: "&zoom=1", with: "&zoom=2")
            
            return BookSearchResult(
                id: item.id,
                title: info.title ?? "Unknown Title",
                authors: info.authors ?? ["Unknown Author"],
                overview: info.description ?? "No description available.",
                coverURL: coverURL,
                pageCount: info.pageCount
            )
        } ?? []
    }
    
    func fetchTrendingMovies() async throws -> [MovieSearchResult] {
        let url = try tmdbURL(path: "/trending/movie/day")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        
        let decodedResponse = try decoder.decode(TMDBResponse.self, from: data)
        return decodedResponse.results.prefix(10).map { 
            MovieSearchResult(id: String($0.id), title: $0.title, overview: $0.overview, posterURL: "https://image.tmdb.org/t/p/w500\($0.poster_path ?? "")", releaseDate: $0.release_date)
        }
    }
    
    func fetchTrendingTVShows() async throws -> [TVSearchResult] {
        let url = try tmdbURL(path: "/trending/tv/day")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        
        let decodedResponse = try decoder.decode(TMDBTVResponse.self, from: data)
        return decodedResponse.results.prefix(10).map { 
            TVSearchResult(id: String($0.id), title: $0.name, overview: $0.overview, posterURL: "https://image.tmdb.org/t/p/w500\($0.poster_path ?? "")", releaseDate: $0.first_air_date)
        }
    }
    
    func fetchMovieDetails(tmdbID: Int) async throws -> (runtime: Int?, genres: [String], voteAverage: Double?, releaseDate: String?) {
        let url = try tmdbURL(path: "/movie/\(tmdbID)")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        
        let details = try decoder.decode(TMDBMovieDetailsResponse.self, from: data)
        return (details.runtime, details.genres.map { $0.name }, details.vote_average, details.release_date)
    }
    
    func fetchTVDetails(tmdbID: Int) async throws -> (seasonsCount: Int, episodesCount: Int, status: String, voteAverage: Double?, seasons: [TMDBSeasonBrief], firstAirDate: String?, nextEpisodeDate: String?, nextEpisodeNumber: Int?, nextSeasonNumber: Int?, tvdbID: Int?) {
        let url = try tmdbURL(path: "/tv/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: "external_ids")])
        
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        
        let details = try decoder.decode(TMDBTVDetailsResponse.self, from: data)
        return (details.number_of_seasons, details.number_of_episodes, details.status, details.vote_average, details.seasons ?? [], details.first_air_date, details.next_episode_to_air?.air_date, details.next_episode_to_air?.episode_number, details.next_episode_to_air?.season_number, details.external_ids?.tvdb_id)
    }

    func fetchSeasonDetails(tmdbID: Int, seasonNumber: Int) async throws -> [TVEpisodeResult] {
        let url = try tmdbURL(path: "/tv/\(tmdbID)/season/\(seasonNumber)")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        
        let decodedResponse = try decoder.decode(TMDBSeasonResponse.self, from: data)
        return decodedResponse.episodes.map { 
            TVEpisodeResult(episodeNumber: $0.episode_number, name: $0.name, overview: $0.overview, airDate: $0.air_date, runtime: $0.runtime)
        }
    }

    func lookupTVMazeID(tvdbID: Int) async throws -> Int? {
        var components = URLComponents(string: "https://api.tvmaze.com/lookup/shows")
        components?.queryItems = [URLQueryItem(name: "thetvdb", value: String(tvdbID))]
        guard let url = components?.url else { throw URLError(.badURL) }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            let show = try decoder.decode(TVMazeShowLookupResponse.self, from: data)
            return show.id
        }
        return nil
    }

    func fetchTVMazeSchedule(tvMazeID: Int) async throws -> (episode: TVMazeEpisode?, timezone: String?, serviceName: String?) {
        var components = URLComponents(string: "https://api.tvmaze.com/shows/\(tvMazeID)")
        components?.queryItems = [URLQueryItem(name: "embed", value: "nextepisode")]
        guard let url = components?.url else { throw URLError(.badURL) }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        
        let decodedResponse = try decoder.decode(TVMazeResponse.self, from: data)
        let serviceName = decodedResponse.webChannel?.name ?? decodedResponse.network?.name
        return (decodedResponse._embedded?.nextepisode, decodedResponse.timezone, serviceName)
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.requestFailed(httpResponse.statusCode)
        }
    }
}
// MARK: - API Response Models

struct TMDBMovieDetailsResponse: Codable {
    let runtime: Int?
    let genres: [TMDBGenre]
    let vote_average: Double?
    let release_date: String?
}

struct TMDBTVDetailsResponse: Codable {
    let number_of_seasons: Int
    let number_of_episodes: Int
    let status: String
    let vote_average: Double?
    let seasons: [TMDBSeasonBrief]?
    let first_air_date: String?
    let next_episode_to_air: TMDBNextEpisode?
    let external_ids: TMDBExternalIDs?
}

struct TMDBExternalIDs: Codable {
    let tvdb_id: Int?
}

struct TMDBNextEpisode: Codable {
    let air_date: String?
    let episode_number: Int?
    let season_number: Int?
}

struct TMDBSeasonBrief: Codable {
    let season_number: Int
    let name: String
    let episode_count: Int
    let air_date: String?
}

struct TMDBSeasonResponse: Codable {
    let episodes: [TMDBEpisodeBrief]
}

struct TMDBEpisodeBrief: Codable {
    let episode_number: Int
    let name: String
    let overview: String
    let air_date: String?
    let runtime: Int?
}

struct TVEpisodeResult: Codable {
    let episodeNumber: Int
    let name: String
    let overview: String
    let airDate: String?
    let runtime: Int?
}

struct TMDBGenre: Codable {
    let name: String
}

struct TMDBResponse: Codable {
    let results: [TMDBMovie]
}

struct TMDBMovie: Codable {
    let id: Int
    let title: String
    let overview: String
    let poster_path: String?
    let release_date: String?
}

struct TMDBTVResponse: Codable {
    let results: [TMDBTV]
}

struct TMDBTV: Codable {
    let id: Int
    let name: String
    let overview: String
    let poster_path: String?
    let first_air_date: String?
}

struct GoogleBooksResponse: Codable {
    let items: [GoogleBookItem]?
}

struct GoogleBookItem: Codable {
    let id: String
    let volumeInfo: GoogleVolumeInfo
}

struct GoogleVolumeInfo: Codable {
    let title: String?
    let authors: [String]?
    let description: String?
    let imageLinks: GoogleImageLinks?
    let pageCount: Int?
}

struct GoogleImageLinks: Codable {
    let thumbnail: String?
}

struct TVMazeShowLookupResponse: Codable {
    let id: Int
}

struct TVMazeResponse: Codable {
    let _embedded: TVMazeEmbedded?
    let network: TVMazeNetwork?
    let webChannel: TVMazeWebChannel?
    
    var timezone: String? {
        network?.country?.timezone ?? webChannel?.country?.timezone
    }
}

struct TVMazeNetwork: Codable {
    let name: String?
    let country: TVMazeCountry?
}

struct TVMazeWebChannel: Codable {
    let name: String?
    let country: TVMazeCountry?
}

struct TVMazeCountry: Codable {
    let timezone: String?
}

struct TVMazeEmbedded: Codable {
    let nextepisode: TVMazeEpisode?
}

struct TVMazeEpisode: Codable {
    let name: String
    let airdate: String
    let airtime: String
    let airstamp: String?
}

// MARK: - UI Search Result Models

struct MovieSearchResult: Identifiable {
    let id: String
    let title: String
    let overview: String
    let posterURL: String?
    let releaseDate: String?
}

struct TVSearchResult: Identifiable {
    let id: String
    let title: String
    let overview: String
    let posterURL: String?
    let releaseDate: String?
}

struct BookSearchResult: Identifiable {
    let id: String
    let title: String
    let authors: [String]
    let overview: String
    let coverURL: String?
    let pageCount: Int?
}
