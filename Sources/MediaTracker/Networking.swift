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

    nonisolated var isTMDBConfigured: Bool {
        UserDefaults.standard.string(forKey: "tmdb_api_key")?.isEmpty == false
    }
    
    private func tmdbURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let key = tmdbApiKey
        guard !key.isEmpty else { throw APIError.missingApiKey("TMDB") }
        var components = URLComponents(string: "https://api.themoviedb.org/3\(path)")
        var items = [
            URLQueryItem(name: "api_key", value: key),
            URLQueryItem(name: "language", value: "en-US"),
            URLQueryItem(name: "region", value: "IN")
        ]
        items.append(contentsOf: queryItems)
        components?.queryItems = items
        guard let url = components?.url else { throw URLError(.badURL) }
        return url
    }

    // MARK: - Generic Search
    private func searchTMDB<T: Codable & TMDBMedia>(path: String, query: String) async throws -> [T] {
        let url = try tmdbURL(path: path, queryItems: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false")
        ])
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let decoded = try decoder.decode(TMDBGenericResponse<T>.self, from: data)
        return decoded.results
    }

    func searchMovies(query: String) async throws -> [MediaSearchResult] {
        let results: [TMDBMovie] = try await searchTMDB(path: "/search/movie", query: query)
        return results.map { $0.toSearchResult() }
    }
    
    func searchTVShows(query: String) async throws -> [MediaSearchResult] {
        let results: [TMDBTV] = try await searchTMDB(path: "/search/tv", query: query)
        return results.map { $0.toSearchResult() }
    }
    
    func fetchTrendingMovies() async throws -> [MediaSearchResult] {
        let url = try tmdbURL(path: "/trending/movie/day")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let decoded = try decoder.decode(TMDBGenericResponse<TMDBMovie>.self, from: data)
        return decoded.results.prefix(10).map { $0.toSearchResult() }
    }
    
    func fetchTrendingTVShows() async throws -> [MediaSearchResult] {
        let url = try tmdbURL(path: "/trending/tv/day")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let decoded = try decoder.decode(TMDBGenericResponse<TMDBTV>.self, from: data)
        return decoded.results.prefix(10).map { $0.toSearchResult() }
    }

    // MARK: - Details
    func fetchMovieDetails(tmdbID: Int) async throws -> (runtime: Int?, genres: [String], voteAverage: Double?, releaseDate: String?, originalLanguage: String?, cast: [CastMemberResult], directors: [CastMemberResult]) {
        let url = try tmdbURL(path: "/movie/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: "credits,release_dates")])
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let details = try decoder.decode(TMDBMovieDetailsResponse.self, from: data)
        let cast = details.credits?.cast.prefix(15).map { 
            CastMemberResult(name: $0.name, character: $0.character, profilePath: $0.profile_path, order: $0.order)
        } ?? []
        
        let directors = details.credits?.crew?.filter { $0.job == "Director" }.map { 
            CastMemberResult(name: $0.name, character: "Director", profilePath: $0.profile_path, order: -1)
        } ?? []
        
        // Find a better release date (Prioritizing India regional data)
        var finalReleaseDate = details.release_date
        if let releaseDates = details.release_dates?.results {
            // Priority 1: Any release date specifically for India (IN)
            if let india = releaseDates.first(where: { $0.iso_3166_1 == "IN" }),
               let localDate = india.release_dates.first {
                finalReleaseDate = localDate.release_date.prefix(10).description
            } 
            // Priority 2: Fallback to US Theatrical if IN is missing
            else if let us = releaseDates.first(where: { $0.iso_3166_1 == "US" }),
                    let theatrical = us.release_dates.first(where: { $0.type == 3 }) {
                finalReleaseDate = theatrical.release_date.prefix(10).description
            }
        }
        
        return (runtime: details.runtime, genres: details.genres.map { $0.name }, voteAverage: details.vote_average, releaseDate: finalReleaseDate, originalLanguage: details.original_language, cast: Array(cast), directors: directors)
        }

        func fetchTVDetails(tmdbID: Int) async throws -> (seasonsCount: Int, episodesCount: Int, status: String, voteAverage: Double?, genres: [String], network: String?, networkLogoPath: String?, originalLanguage: String?, seasons: [TMDBSeasonBrief], firstAirDate: String?, nextEpisodeDate: String?, nextEpisodeNumber: Int?, nextSeasonNumber: Int?, tvdbID: Int?, cast: [CastMemberResult], creators: [CastMemberResult]) {
        let url = try tmdbURL(path: "/tv/\(tmdbID)", queryItems: [URLQueryItem(name: "append_to_response", value: "external_ids,credits")])
        let (data, response) = try await URLSession.shared.data(from: url)
        try validateResponse(response)
        let d = try decoder.decode(TMDBTVDetailsResponse.self, from: data)
        let cast = d.credits?.cast.prefix(15).map { 
            CastMemberResult(name: $0.name, character: $0.character, profilePath: $0.profile_path, order: $0.order)
        } ?? []
        let creators = d.created_by?.map { 
            CastMemberResult(name: $0.name, character: "Creator", profilePath: $0.profile_path, order: -1)
        } ?? []
        let network = d.networks?.first
        return (d.number_of_seasons, d.number_of_episodes, d.status, d.vote_average, d.genres.map { $0.name }, network?.name, network?.logo_path, d.original_language, d.seasons ?? [], d.first_air_date, d.next_episode_to_air?.air_date, d.next_episode_to_air?.episode_number, d.next_episode_to_air?.season_number, d.external_ids?.tvdb_id, Array(cast), creators)
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
protocol TMDBMedia: Codable {
    var id: Int { get }
    var overview: String { get }
    var poster_path: String? { get }
    var backdrop_path: String? { get }
    var genre_ids: [Int]? { get }
    var displayTitle: String { get }
    var releaseDateString: String? { get }
    var mediaType: MediaType { get }
}

extension TMDBMedia {
    var backdrop_path: String? { nil } // Default implementation if not all have it
    
    func toSearchResult() -> MediaSearchResult {
        let genreList = genre_ids?.compactMap { id in
            mediaType == .movie ? TMDBGenreMap.movieGenres[id] : TMDBGenreMap.tvGenres[id]
        }.prefix(2) ?? []
        
        var languageCode: String? = nil
        if let movie = self as? TMDBMovie {
            languageCode = movie.original_language
        } else if let tv = self as? TMDBTV {
            languageCode = tv.original_language
        }

        return MediaSearchResult(
            id: String(id),
            title: displayTitle,
            overview: overview,
            posterURL: poster_path != nil ? "https://image.tmdb.org/t/p/w342\(poster_path!)" : nil,
            releaseDate: releaseDateString,
            genres: Array(genreList),
            type: mediaType,
            originalLanguage: languageCode
        )
    }
}

struct MediaSearchResult: Identifiable, Codable {
    let id: String
    let title: String
    let overview: String
    let posterURL: String?
    let releaseDate: String?
    let genres: [String]
    let type: MediaType
    let originalLanguage: String?
}

struct TMDBGenericResponse<T: Codable>: Codable {
    let results: [T]
}

struct TMDBMovie: TMDBMedia {
    let id: Int
    let title: String
    let overview: String
    let poster_path: String?
    let backdrop_path: String?
    let release_date: String?
    let genre_ids: [Int]?
    let original_language: String?
    
    var displayTitle: String { title }
    var releaseDateString: String? { release_date }
    var mediaType: MediaType { .movie }
}

struct TMDBTV: TMDBMedia {
    let id: Int
    let name: String
    let overview: String
    let poster_path: String?
    let backdrop_path: String?
    let first_air_date: String?
    let genre_ids: [Int]?
    let original_language: String?
    
    var displayTitle: String { name }
    var releaseDateString: String? { first_air_date }
    var mediaType: MediaType { .tvShow }
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
    let runtime: Int?, genres: [TMDBGenre], vote_average: Double?, release_date: String?
    let original_language: String?
    let credits: TMDBCreditsResponse?
    let release_dates: TMDBReleaseDatesResponse?
}

struct TMDBReleaseDatesResponse: Codable {
    let results: [TMDBRegionalReleaseDates]
}

struct TMDBRegionalReleaseDates: Codable {
    let iso_3166_1: String
    let release_dates: [TMDBReleaseDateDetail]
}

struct TMDBReleaseDateDetail: Codable {
    let release_date: String
    let type: Int // 3 is Theatrical
}

struct TMDBTVDetailsResponse: Codable {
    let number_of_seasons: Int, number_of_episodes: Int, status: String, vote_average: Double?, genres: [TMDBGenre]
    let original_language: String?
    let networks: [TMDBNetwork]?
    let created_by: [TMDBPerson]?
    let seasons: [TMDBSeasonBrief]?, first_air_date: String?, next_episode_to_air: TMDBNextEpisode?, external_ids: TMDBExternalIDs?, credits: TMDBCreditsResponse?
}

struct TMDBPerson: Codable {
    let name: String
    let profile_path: String?
}

struct TMDBNetwork: Codable {
    let name: String
    let logo_path: String?
}

struct TMDBCreditsResponse: Codable {
    let cast: [TMDBMovieCastMember]
    let crew: [TMDBMovieCrewMember]?
}

struct TMDBMovieCrewMember: Codable {
    let name: String
    let job: String
    let profile_path: String?
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

struct TVEpisodeResult: Codable { let episodeNumber: Int, name: String, overview: String, airDate: String?, runtime: Int? }
