import Foundation
import SwiftData

@Model
final class SeasonCastMember {
    var seasonNumber: Int
    var tmdbPersonID: Int
    var name: String
    var characterName: String
    var profileURL: String?
    /// Number of episodes this person appeared in within this season.
    /// Drives the "counts a season" floor and the per-season cast sort.
    var episodeCount: Int
    var order: Int
    var showID: Int
    @Attribute(.unique) var uniqueID: String?
    var season: TVSeason?

    init(seasonNumber: Int, tmdbPersonID: Int, name: String, characterName: String, profileURL: String? = nil, episodeCount: Int, order: Int = 0, showID: Int) {
        self.seasonNumber = seasonNumber
        self.tmdbPersonID = tmdbPersonID
        self.name = name
        self.characterName = characterName
        self.profileURL = profileURL
        self.episodeCount = episodeCount
        self.order = order
        self.showID = showID
        self.uniqueID = "\(showID)_\(seasonNumber)_\(tmdbPersonID)"
    }

    /// Whether this actor's presence in this season clears the "counts a season" floor.
    /// Floor = min(2, 10% of the season's episodes). Seasons with <10 episodes keep
    /// even one-episode cameos; longer seasons require >2 appearances.
    var qualifiesForTaste: Bool {
        let seasonTotal = max(season?.totalEpisodesCount ?? 0, season?.episodeCount ?? 0)
        let total = max(seasonTotal, 1)
        let floor = min(2.0, 0.10 * Double(total))
        return Double(episodeCount) > floor
    }
}
