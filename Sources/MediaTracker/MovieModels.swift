import Foundation

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

struct TMDBMovieDetailsResponse: Codable {
    let runtime: Int?, genres: [TMDBGenre], vote_average: Double?, release_date: String?, backdrop_path: String?, poster_path: String?
    let overview: String?
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
