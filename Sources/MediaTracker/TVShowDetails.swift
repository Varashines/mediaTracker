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
                firstUnwatched: findFirstUnwatched(),
                totalRuntime: item?.cachedRuntime ?? 0
            )
        }

        var total = 0
        var watched = 0
        var aired = 0
        var runtime = 0
        var firstUnwatchedEpisode: TVEpisode? = nil
        
        // Ensure seasons are sorted for consistent traversal
        let sortedSeasons = seasons.sorted { $0.seasonNumber < $1.seasonNumber }
        
        for season in sortedSeasons {
            let seasonEpisodes = season.episodes
            // Sync season counts
            season.totalEpisodesCount = seasonEpisodes.count
            season.watchedEpisodesCount = seasonEpisodes.filter { $0.isWatched }.count

            // Standard progress calculations usually exclude Specials (Season 0)
            if season.seasonNumber > 0 {
                total += season.totalEpisodesCount
                watched += season.watchedEpisodesCount
                
                // Ensure episodes are sorted
                let sortedEpisodes = seasonEpisodes.sorted { $0.episodeNumber < $1.episodeNumber }
                
                for ep in sortedEpisodes {
                    if ep.isWatched {
                        runtime += ep.runtime ?? 0
                    } else if firstUnwatchedEpisode == nil {
                        firstUnwatchedEpisode = ep
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
            firstUnwatched: firstUnwatchedEpisode,
            totalRuntime: runtime
        )
    }

    /// Optimized lookup for the next episode to watch
    private func findFirstUnwatched() -> TVEpisode? {
        if let context = modelContext {
            let showID = self.tmdbID
            var descriptor = FetchDescriptor<TVEpisode>(
                predicate: #Predicate { $0.showID == showID && !$0.isWatched && $0.seasonNumber > 0 },
                sortBy: [SortDescriptor(\.seasonNumber), SortDescriptor(\.episodeNumber)]
            )
            descriptor.fetchLimit = 1
            if let first = try? context.fetch(descriptor).first {
                return first
            }
        }
        
        // Fallback to relationship scan if context is unavailable
        return seasons
            .filter { $0.seasonNumber > 0 }
            .flatMap { $0.episodes }
            .filter { !$0.isWatched }
            .sorted { 
                if $0.seasonNumber != $1.seasonNumber {
                    return $0.seasonNumber < $1.seasonNumber
                }
                return $0.episodeNumber < $1.episodeNumber
            }
            .first
    }

    func refreshCounts(force: Bool = false) {
        _ = calculateProgress(forceRecalculate: force)
    }
    
    func recalculateCachedProperties(triggerSync: Bool = true, force: Bool = false) {
        _ = calculateProgress(forceRecalculate: force)
        if triggerSync { item?.syncCachedProperties(force: force) }
    }
}
