import Foundation
import SwiftData

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
