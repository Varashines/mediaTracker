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
