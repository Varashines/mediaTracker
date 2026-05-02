import Foundation

// MARK: - TMDB Base Protocol
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
    var backdrop_path: String? { nil } // Default implementation
    
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
            posterURL: APIClient.tmdbImageURL(path: poster_path),
            releaseDate: releaseDateString,
            genres: Array(genreList),
            type: mediaType,
            originalLanguage: languageCode
        )
    }
}

// MARK: - Search Results
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

// MARK: - Genre Mappings
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

// MARK: - Detailed Responses
struct TMDBMovieDetailsResponse: Codable {
    let runtime: Int?, genres: [TMDBGenre], vote_average: Double?, release_date: String?, backdrop_path: String?, poster_path: String?
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
    let number_of_seasons: Int, number_of_episodes: Int, status: String, vote_average: Double?, genres: [TMDBGenre], backdrop_path: String?, poster_path: String?
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

struct TMDBExternalIDs: Codable { let tvdb_id: Int? }
struct TMDBNextEpisode: Codable { let air_date: String?, episode_number: Int?, season_number: Int? }
struct TMDBSeasonBrief: Codable { let season_number: Int, name: String, episode_count: Int, air_date: String? }
struct TMDBSeasonResponse: Codable { let episodes: [TMDBEpisodeBrief] }
struct TMDBEpisodeBrief: Codable { let episode_number: Int, name: String, overview: String, air_date: String?, runtime: Int? }
struct TMDBGenre: Codable { let name: String }

// MARK: - TVMaze Responses
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

// MARK: - Client Result Wrappers
struct CastMemberResult: Codable {
    let name: String
    let character: String
    let profilePath: String?
    let order: Int
}

struct TVEpisodeResult: Codable { let episodeNumber: Int, name: String, overview: String, airDate: String?, runtime: Int? }

struct TMDBPersonSearchEntry: Codable {
    let profile_path: String?
}

struct MovieDetailsResult {
    let runtime: Int?
    let genres: [String]
    let voteAverage: Double?
    let releaseDate: String?
    let backdropPath: String?
    let posterPath: String?
    let originalLanguage: String?
    let cast: [CastMemberResult]
    let directors: [CastMemberResult]
}

struct TVDetailsResult {
    let seasonsCount: Int
    let episodesCount: Int
    let status: String
    let voteAverage: Double?
    let genres: [String]
    let backdropPath: String?
    let posterPath: String?
    let network: String?
    let networkLogoPath: String?
    let originalLanguage: String?
    let seasons: [TMDBSeasonBrief]
    let firstAirDate: String?
    let nextEpisodeDate: String?
    let nextEpisodeNumber: Int?
    let nextSeasonNumber: Int?
    let tvdbID: Int?
    let cast: [CastMemberResult]
    let creators: [CastMemberResult]
}
