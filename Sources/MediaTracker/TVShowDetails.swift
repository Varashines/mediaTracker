import Foundation
import SwiftData

@Model
final class TVShowDetails {
    var tmdbID: Int
    var tvMazeID: Int?
    var numberOfSeasons: Int?
    var numberOfEpisodes: Int?
    var status: String?
    var voteAverage: Double?
    var genres: [String] = []
    var network: String?
    var networkLogoPath: String?
    var originalLanguage: String?
    var creators: [String] = []
    var timezone: String?
    var remainingEpisodesCount: Int?
    var nextEpisodeDate: Date?
    var nextEpisodeNumber: Int?
    var nextSeasonNumber: Int?
    var nextEpisodeTime: String?

    /// Phase 2 Optimization: Denormalized counts for O(1) progress tracking
    var totalEpisodesCount: Int = 0
    var watchedEpisodesCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \TVSeason.tvShowDetails) var seasons: [TVSeason] = []
    @Relationship(deleteRule: .cascade, inverse: \CastMember.tvShowDetails) var cast: [CastMember] = []
    var item: MediaItem?

    init(tmdbID: Int) {
        self.tmdbID = tmdbID
    }

    func refreshCounts() {
        var total = 0
        var watched = 0
        for season in seasons {
            season.refreshCounts()
            // Progress bar and overall counts typically exclude Specials (S0)
            if season.seasonNumber > 0 {
                total += season.totalEpisodesCount
                watched += season.watchedEpisodesCount
            }
        }
        self.totalEpisodesCount = total
        self.watchedEpisodesCount = watched
    }
    
    func recalculateCachedProperties(triggerSync: Bool = true) {
        refreshCounts()
        if triggerSync { item?.syncCachedProperties() }
    }
}
