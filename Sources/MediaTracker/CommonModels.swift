import Foundation

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

// MARK: - Client Result Wrappers
struct CastMemberResult: Codable {
    let name: String
    let character: String
    let profilePath: String?
    let order: Int
}

struct TVEpisodeResult: Codable { let episodeNumber: Int, name: String?, overview: String?, airDate: String?, runtime: Int? }

struct ProductionCompanyResult: Codable {
    let name: String
    let logoPath: String?
}

struct MovieDetailsResult {
    let runtime: Int?
    let genres: [String]
    let voteAverage: Double?
    let rottenTomatoesScore: Int?
    let imdbID: String?
    let releaseDate: String?
    let backdropPath: String?
    let posterPath: String?
    let overview: String?
    let originalLanguage: String?
    let cast: [CastMemberResult]
    let directors: [CastMemberResult]
    let productionCompanies: [ProductionCompanyResult]
}

struct TVDetailsResult {
    let seasonsCount: Int
    let episodesCount: Int
    let status: String
    let voteAverage: Double?
    let imdbID: String?
    let genres: [String]
    let backdropPath: String?
    let posterPath: String?
    let overview: String?
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
