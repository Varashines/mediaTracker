import Foundation

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
