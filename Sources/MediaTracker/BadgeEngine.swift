import Foundation

// MARK: - Badge Logic Engine
/// Centralized engine for calculating semantic badges for Movies and TV Shows.
struct BadgeEngine {
    struct BadgeResult: Equatable {
        let label: String
        let icon: String
        let isSparkle: Bool
    }

    static func calculateBadge(for item: MediaItem) -> BadgeResult? {
        let now = Date()

        // 1. Availability / Release Timing (Highest Priority)
        if let airDate = item.cachedNextAiringDate {
            let timeToAir = airDate.timeIntervalSinceNow

            // NEW: Released within last 48 hours
            if timeToAir <= 0 && timeToAir >= -172800 {
                return BadgeResult(label: "NEW", icon: "sparkles", isSparkle: true)
            }

            // SOON: Releasing within next 48 hours
            if timeToAir > 0 && timeToAir <= 172800 {
                return BadgeResult(label: "SOON", icon: "clock.badge.fill", isSparkle: false)
            }
        }

        // 2. TV Show Specific Events
        if item.type == .tvShow, let tv = item.tvShowDetails {
            // Sort relevant seasons
            let relevantSeasons = tv.seasons.filter { $0.seasonNumber > 0 }.sorted {
                $0.seasonNumber < $1.seasonNumber
            }

            // Single pass to find next unwatched and capture its season episodes
            var firstUnwatched: TVEpisode? = nil
            var unwatchedSeasonEpisodes: [TVEpisode] = []
            var totalAiredUnwatched = 0

            for season in relevantSeasons {
                let sortedEps = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
                for ep in sortedEps {
                    if !ep.isWatched {
                        if firstUnwatched == nil {
                            firstUnwatched = ep
                            unwatchedSeasonEpisodes = sortedEps
                        }
                        if (ep.airDateAsDate ?? .distantFuture) <= now {
                            totalAiredUnwatched += 1
                        }
                    }
                }
            }

            if let next = firstUnwatched {
                let airDate = next.airDateAsDate
                let timeToAir = airDate?.timeIntervalSinceNow ?? .infinity
                let isAvailable = (airDate != nil) && (airDate! <= now)

                // Recency Window for Events (14 days)
                let isRecent = airDate != nil && airDate! >= now.addingTimeInterval(-86400 * 14)
                let isImminent = timeToAir > 0 && timeToAir <= 172800 * 12

                // PREMIERE
                if next.episodeNumber == 1 && (isAvailable || isImminent) && isRecent {
                    let label = next.seasonNumber == 1 ? "SERIES PREMIERE" : "SEASON PREMIERE"
                    let icon =
                        next.seasonNumber == 1 ? "star.square.fill" : "play.square.stack.fill"
                    return BadgeResult(label: label, icon: icon, isSparkle: true)
                }

                // BINGE DROP: Full season released in last 5 days
                let seasonUnwatched = unwatchedSeasonEpisodes.filter { !$0.isWatched }
                if seasonUnwatched.count > 1 {
                    let firstDate = seasonUnwatched[0].airDate
                    let isSameDate = seasonUnwatched.allSatisfy {
                        $0.airDate == firstDate && $0.airDate != nil
                    }
                    if isSameDate, let date = seasonUnwatched[0].airDateAsDate {
                        let daysDiff = date.timeIntervalSinceNow / 86400
                        if daysDiff >= -5 && daysDiff <= 0 {
                            return BadgeResult(
                                label: "BINGE DROP", icon: "sparkles.tv", isSparkle: true)
                        }
                    }
                }

                // FINALE
                if let season = next.season, next.episodeNumber == season.episodeCount && isRecent {
                    return BadgeResult(label: "FINALE", icon: "flag.checkered", isSparkle: true)
                }

                // BINGE (Backlog)
                if isAvailable && totalAiredUnwatched > 5 {
                    return BadgeResult(
                        label: "BINGE", icon: "play.square.stack.fill", isSparkle: false)
                }
            }
        }

        // 3. Fallback for Movies / General Recency
        if let release = item.releaseDate {
            let timeToRelease = release.timeIntervalSinceNow

            // Movie "NEW" threshold check
            if timeToRelease <= 0 && timeToRelease >= -172800 {
                return BadgeResult(label: "NEW", icon: "sparkles", isSparkle: true)
            }

            if timeToRelease <= 0 && timeToRelease > -604800 {
                return BadgeResult(label: "RECENT", icon: "star.fill", isSparkle: false)
            }
        }

        return nil
    }
}
