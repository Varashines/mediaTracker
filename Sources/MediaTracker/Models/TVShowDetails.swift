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
    var imdbRating: Double?
    var rottenTomatoesScore: Int?
    var contentRating: String?
    var genres: [String] = []
    var showType: String?
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
        // Defensive: skip seasons/episodes deleted during background context merges
        let sortedSeasons = seasons
            .liveModels
            .sorted { $0.seasonNumber < $1.seasonNumber }
        
        for season in sortedSeasons {
            let seasonEpisodes = season.episodes.liveModels
            // Ensure episodes are sorted
            let sortedEpisodes = seasonEpisodes.sorted { $0.episodeNumber < $1.episodeNumber }
            
            var seasonWatched = 0
            // Sync season counts and compute progress in a single pass
            season.totalEpisodesCount = max(season.episodeCount, seasonEpisodes.count)

            // Standard progress calculations usually exclude Specials (Season 0)
            if season.seasonNumber > 0 {
                total += season.totalEpisodesCount
                
                for ep in sortedEpisodes {
                    if ep.isWatched {
                        watched += 1
                        seasonWatched += 1
                        runtime += ep.runtime ?? 0
                    } else if firstUnwatchedEpisode == nil {
                        firstUnwatchedEpisode = ep
                    }
                    
                    if let airDate = ep.airDateValue, airDate <= now {
                        aired += 1
                    }
                }
            } else {
                // Still count watched for Specials season display
                for ep in sortedEpisodes where ep.isWatched {
                    seasonWatched += 1
                }
            }
            season.watchedEpisodesCount = seasonWatched
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
            .liveModels.filter { $0.seasonNumber > 0 }
            .flatMap { $0.episodes.liveModels }
            .filter { !$0.isWatched }
            .sorted { 
                if $0.seasonNumber != $1.seasonNumber {
                    return $0.seasonNumber < $1.seasonNumber
                }
                return $0.episodeNumber < $1.episodeNumber
            }
            .first
    }
    
    func recalculateCachedProperties(triggerSync: Bool = true, force: Bool = false) {
        _ = calculateProgress(forceRecalculate: force)
        // Invalidate badge scan cache when episodes change — this is the correct
        // place since episode state is what makes the scan stale.
        if let showID = item?.persistentModelID {
            BadgeEngine.invalidateScan(for: showID)
        }
        if triggerSync {
            // Pass force: false to avoid redundant full scan — denormalized counts are already updated by calculateProgress
            item?.syncCachedProperties(force: false)
        }
    }
}
