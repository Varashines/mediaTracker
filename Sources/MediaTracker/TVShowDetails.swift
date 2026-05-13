import Foundation
import SwiftData

struct TVProgressResult {
    let totalCount: Int
    let watchedCount: Int
    let remainingCount: Int
    let firstUnwatched: TVEpisode?
    let totalRuntime: Int
}

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

    func calculateProgress(now: Date = Date(), forceRecalculate: Bool = false) -> TVProgressResult {
        // Optimization: Return cached results if we already have them and don't need a deep scan
        if !forceRecalculate && totalEpisodesCount > 0 {
            return TVProgressResult(
                totalCount: totalEpisodesCount,
                watchedCount: watchedEpisodesCount,
                remainingCount: remainingEpisodesCount ?? 0,
                firstUnwatched: nil, // Note: firstUnwatched still requires a scan if needed
                totalRuntime: 0 // Note: totalRuntime also requires a scan if needed
            )
        }

        var total = 0
        var watched = 0
        var aired = 0
        var runtime = 0
        var firstUnwatched: TVEpisode? = nil
        
        // Ensure seasons are sorted for consistent traversal
        let sortedSeasons = seasons.sorted { $0.seasonNumber < $1.seasonNumber }
        
        for season in sortedSeasons {
            // Update individual season denormalized counts
            let seasonEpisodes = season.episodes
            season.totalEpisodesCount = seasonEpisodes.count
            season.watchedEpisodesCount = seasonEpisodes.filter { $0.isWatched }.count

            // Standard progress calculations usually exclude Specials (Season 0)
            if season.seasonNumber > 0 {
                // Ensure episodes are sorted
                let sortedEpisodes = seasonEpisodes.sorted { $0.episodeNumber < $1.episodeNumber }
                
                for ep in sortedEpisodes {
                    total += 1
                    if ep.isWatched {
                        watched += 1
                        runtime += ep.runtime ?? 0
                    } else if firstUnwatched == nil {
                        firstUnwatched = ep
                    }
                    
                    if let airDate = ep.airDateValue, airDate <= now {
                        aired += 1
                    }
                }
            }
        }
        
        let remaining = max(0, aired - watched)
        
        // Update denormalized properties
        self.totalEpisodesCount = total
        self.watchedEpisodesCount = watched
        self.remainingEpisodesCount = remaining
        
        return TVProgressResult(
            totalCount: total,
            watchedCount: watched,
            remainingCount: remaining,
            firstUnwatched: firstUnwatched,
            totalRuntime: runtime
        )
    }

    func refreshCounts() {
        _ = calculateProgress()
    }
    
    func recalculateCachedProperties(triggerSync: Bool = true) {
        _ = calculateProgress()
        if triggerSync { item?.syncCachedProperties() }
    }
}
