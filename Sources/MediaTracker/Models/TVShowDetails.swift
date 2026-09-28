import Foundation
import SwiftData

struct TVProgressResult {
    let totalCount: Int
    let watchedCount: Int
    let remainingCount: Int
    let firstUnwatched: TVEpisode?
    let totalRuntime: Int
    /// Mean over episodes with a known runtime (all regular seasons, watched
    /// or not). Never divide a watched-only sum by the full episode count.
    let averageEpisodeRuntime: Int?
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
                totalRuntime: item?.cachedRuntime ?? 0,
                averageEpisodeRuntime: item?.cachedEpisodeRuntime
            )
        }

        var total = 0
        var watched = 0
        var aired = 0
        var runtime = 0
        var knownRuntimeSum = 0
        var knownRuntimeCount = 0
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

                    if let epRuntime = ep.runtime, epRuntime > 0 {
                        knownRuntimeSum += epRuntime
                        knownRuntimeCount += 1
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
            totalRuntime: runtime,
            averageEpisodeRuntime: knownRuntimeCount > 0 ? knownRuntimeSum / knownRuntimeCount : nil
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
    
    /// Earliest durable first-watch date across all known episodes.
    ///
    /// Deliberately reads `firstWatchedDate` only, never the
    /// `watchedDate`/`lastWatchedDate` projection: mid-rewatch those hold the
    /// *rewatch* date, so falling back to them would pin the title's first-watch
    /// date to the current pass. A title simply has no first-watch date until
    /// the ledger (or the backfill migration) supplies one.
    var earliestEpisodeFirstWatchDate: Date? {
        var earliest: Date?
        for season in seasons.liveModels {
            for episode in season.episodes.liveModels {
                guard let date = episode.firstWatchedDate else { continue }
                if let current = earliest {
                    if date < current { earliest = date }
                } else {
                    earliest = date
                }
            }
        }
        return earliest
    }

    /// Earliest known watch date including the projection. Display-only — never
    /// use this to derive a durable first-watch date.
    var earliestEpisodeKnownWatchDate: Date? {
        var earliest: Date?
        for season in seasons.liveModels {
            for episode in season.episodes.liveModels {
                guard let date = episode.firstKnownWatchDate else { continue }
                if let current = earliest {
                    if date < current { earliest = date }
                } else {
                    earliest = date
                }
            }
        }
        return earliest
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
            item?.syncCachedProperties(dirty: [.progress, .badge])
        }
    }

    /// The next episode worth telling the user about: the earliest-aired episode
    /// that is both unwatched and not yet aired.
    ///
    /// Derived from local watch state rather than `nextEpisodeNumber`, which is a
    /// TMDB/TVMaze snapshot of what the *network* airs next. It is never revised
    /// when an episode is marked watched, so it kept naming episodes already seen
    /// (13 of 32 upcoming shows before this existed) and could name an episode
    /// whose cached date had already passed, which silently skipped the
    /// notification entirely.
    ///
    /// Specials (season 0) are excluded, matching progress calculations and every
    /// episode-marking path.
    func nextUnwatchedUnairedEpisode(now: Date = Date()) -> TVEpisode? {
        let upcoming: [(episode: TVEpisode, air: Date)] = seasons.liveModels
            .filter { $0.seasonNumber > 0 }
            .flatMap { $0.episodes.liveModels }
            .compactMap { episode in
                guard !episode.isWatched,
                      let air = episode.airDateAsDate,
                      air > now else { return nil }
                return (episode, air)
            }
        return upcoming.min { $0.air < $1.air }?.episode
    }

    /// The next episode to mark watched, in season/episode order, regardless of
    /// whether it has aired. This is the in-app rule (detail-view spacebar and
    /// context menu), exposed so notification actions resolve their target the
    /// same way instead of trusting the season/episode numbers in the payload.
    func nextUnwatchedEpisode() -> TVEpisode? {
        seasons.liveModels
            .filter { $0.seasonNumber > 0 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
            .flatMap { $0.episodes.liveModels }
            .sorted { $0.episodeNumber < $1.episodeNumber }
            .first { !$0.isWatched }
    }

    /// The soonest season whose last episode is still unwatched and airs within
    /// `window` — the cue for a "season's out, go binge" notification.
    ///
    /// The `episodeCount >= 3` guard is load-bearing. A season that hasn't been
    /// fully fetched reports `episodeCount` of 1 or 2, so "highest episode number"
    /// is really the premiere, and treating that as a finale produced alerts for
    /// Abbott Elementary S6E1, 9-1-1 S10E1, Silo S4E1 and similar. 11 of 45
    /// candidates were that false positive. Seasons that short are treated as
    /// unsynced rather than genuinely short.
    func upcomingSeasonFinale(within window: TimeInterval, now: Date = Date()) -> (season: TVSeason, episode: TVEpisode, airDate: Date)? {
        let cutoff = now.addingTimeInterval(window)
        var soonest: (season: TVSeason, episode: TVEpisode, airDate: Date)?

        for season in seasons.liveModels where season.seasonNumber > 0 {
            guard season.episodeCount >= 3,
                  let finalEpisode = season.episodes.liveModels.first(where: { $0.episodeNumber == season.episodeCount }),
                  !finalEpisode.isWatched,
                  let airDate = finalEpisode.airDateAsDate,
                  airDate > now,
                  airDate <= cutoff else { continue }
            if soonest == nil || airDate < soonest!.airDate {
                soonest = (season, finalEpisode, airDate)
            }
        }
        return soonest
    }
}
