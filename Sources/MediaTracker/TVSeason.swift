import Foundation
import SwiftData

@Model
final class TVSeason {
    var seasonNumber: Int
    var name: String
    var episodeCount: Int
    var airDate: String?
    var showID: Int?
    var uniqueID: String?
    var tvShowDetails: TVShowDetails?
    @Relationship(deleteRule: .cascade, inverse: \TVEpisode.season) var episodes: [TVEpisode] = []

    init(seasonNumber: Int, name: String, episodeCount: Int, airDate: String? = nil, showID: Int? = nil) {
        self.seasonNumber = seasonNumber
        self.name = name
        self.episodeCount = episodeCount
        self.airDate = airDate
        self.showID = showID
        if let showID = showID { self.uniqueID = "\(showID)_\(seasonNumber)" }
    }
}
