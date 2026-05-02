import Foundation
import SwiftData

@Model
final class MovieDetails {
    var tmdbID: Int
    var runtime: Int?
    var genres: [String] = []
    var voteAverage: Double?
    var originalLanguage: String?
    var creators: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \CastMember.movieDetails) var cast: [CastMember] = []
    var item: MediaItem?

    init(tmdbID: Int) {
        self.tmdbID = tmdbID
    }
}
