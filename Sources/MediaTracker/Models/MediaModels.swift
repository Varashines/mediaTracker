import Foundation
import SwiftData

// MARK: - Movie Details (Database Model)

@Model
final class MovieDetails {
    var tmdbID: Int
    var runtime: Int?
    var genres: [String] = []
    var voteAverage: Double?
    var rottenTomatoesScore: Int?
    var imdbRating: Double?
    var contentRating: String?
    var originalLanguage: String?
    var creators: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \CastMember.movieDetails) var cast: [CastMember] = []
    var network: String?
    var networkLogoPath: String?
    var item: MediaItem?

    init(tmdbID: Int) {
        self.tmdbID = tmdbID
    }
}

// MARK: - Movie Models (API Structures)

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

struct TMDBProductionCompany: Codable {
    let id: Int
    let name: String
    let logo_path: String?
    let origin_country: String?
}

struct TMDBMovieDetailsResponse: Codable {
    let runtime: Int?, genres: [TMDBGenre], vote_average: Double?, release_date: String?, backdrop_path: String?, poster_path: String?
    let overview: String?
    let original_language: String?
    let credits: TMDBCreditsResponse?
    let release_dates: TMDBReleaseDatesResponse?
    let production_companies: [TMDBProductionCompany]?
    let external_ids: TMDBExternalIDs?
}

struct OMDBFullData: Sendable {
    let rottenTomatoesScore: Int?
    let imdbRating: Double?
    let contentRating: String?
}

struct OMDBResponse: Codable {
    let response: String?
    let ratings: [OMDBRating]?
    let imdbRating: String?
    let rated: String?
    
    struct OMDBRating: Codable {
        let source: String
        let value: String
        
        enum CodingKeys: String, CodingKey {
            case source = "Source"
            case value = "Value"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case response = "Response"
        case ratings = "Ratings"
        case imdbRating
        case rated = "Rated"
    }
    
    var isSuccess: Bool { response == "True" }
    
    var toFullData: OMDBFullData? {
        guard isSuccess else { return nil }
        let rtScore = ratings?.first(where: { $0.source == "Rotten Tomatoes" })
            .map { $0.value.trimmingCharacters(in: CharacterSet(charactersIn: "%")) }
            .flatMap(Int.init)
        let imdb = imdbRating.flatMap(Double.init)
        return OMDBFullData(rottenTomatoesScore: rtScore, imdbRating: imdb, contentRating: rated)
    }
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

// MARK: - TV Models (API Structures)

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

struct TMDBTVDetailsResponse: Codable {
    let number_of_seasons: Int, number_of_episodes: Int, status: String, vote_average: Double?, genres: [TMDBGenre], backdrop_path: String?, poster_path: String?
    let overview: String?
    let original_language: String?
    let networks: [TMDBNetwork]?
    let created_by: [TMDBPerson]?
    let seasons: [TMDBSeasonBrief]?, first_air_date: String?, next_episode_to_air: TMDBNextEpisode?, external_ids: TMDBExternalIDs?, credits: TMDBCreditsResponse?, aggregate_credits: TMDBAggregateCreditsResponse?
}

// MARK: - TV Season (Database Model)

@Model
final class TVSeason {
    var seasonNumber: Int
    var name: String
    var episodeCount: Int
    var airDate: String?
    var showID: Int?
    @Attribute(.unique) var uniqueID: String?
    var tvShowDetails: TVShowDetails?
    @Relationship(deleteRule: .cascade, inverse: \TVEpisode.season) var episodes: [TVEpisode] = []

    /// Denormalized counts for O(1) UI performance
    var watchedEpisodesCount: Int = 0
    var totalEpisodesCount: Int = 0

    init(seasonNumber: Int, name: String, episodeCount: Int, airDate: String? = nil, showID: Int? = nil) {
        self.seasonNumber = seasonNumber
        self.name = name
        self.episodeCount = episodeCount
        self.airDate = airDate
        self.showID = showID
        if let showID = showID { self.uniqueID = "\(showID)_\(seasonNumber)" }
    }
}
