import Foundation

// MARK: - Badge Logic Engine
/// Centralized engine for calculating semantic badges for Movies and TV Shows.
struct BadgeEngine {
    struct BadgeResult: Equatable {
        let label: String
        let isSparkle: Bool
    }

    static func calculateBadge(for item: MediaItem, now: Date = Date()) -> BadgeResult? {
        // --- LEVEL 1: MILESTONE EVENTS (Highest Priority) ---
        // These are checked against the user's NEXT unwatched episode to ensure relevance.
        var nextToWatch: TVEpisode? = nil
        var airedOnSameDayCount = 0
        var recentlyWatchedCount = 0
        let fortyEightHoursAgo = now.addingTimeInterval(-172800)

        if item.type == .tvShow, let tv = item.tvShowDetails {
            // Find the absolute next unwatched episode regardless of date, efficiently
            let sortedSeasons = tv.seasons.sorted { $0.seasonNumber < $1.seasonNumber }
            for season in sortedSeasons {
                let sortedEpisodes = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
                for ep in sortedEpisodes {
                    if !ep.isWatched {
                        if nextToWatch == nil {
                            nextToWatch = ep
                            airedOnSameDayCount = 1
                        } else if ep.airDate == nextToWatch?.airDate {
                            airedOnSameDayCount += 1
                        }
                    } else if let lastWatched = ep.lastWatchedDate, lastWatched >= fortyEightHoursAgo {
                        recentlyWatchedCount += 1
                    }
                }
            }
            
            if let nextToWatch = nextToWatch {
                if let airDate = nextToWatch.airDateAsDate {
                    let daysSinceAir = now.timeIntervalSince(airDate) / 86400
                    // Milestone window: Within last 14 days or next 14 days (widened for hype)
                    let isRelevantMilestone = daysSinceAir >= -14 && daysSinceAir <= 14
                    
                    if isRelevantMilestone {
                        // 1. FINALE - Check if this is the last episode of the season
                        if let season = nextToWatch.season, nextToWatch.episodeNumber == season.episodeCount {
                            return BadgeResult(label: "FINALE", isSparkle: true)
                        }

                        // 2. SEASON/SERIES PREMIERE
                        if nextToWatch.episodeNumber == 1 {
                            let label = nextToWatch.seasonNumber == 1 ? "SERIES PREMIERE" : "SEASON PREMIERE"
                            return BadgeResult(label: label, isSparkle: true)
                        }
                        
                        // 3. BINGE DROP (Multiple episodes aired on same day for the user's current progress)
                        if airedOnSameDayCount > 1 {
                            return BadgeResult(label: "BINGE DROP", isSparkle: true)
                        }
                    }
                }
            }
        }

        // --- LEVEL 2: RELEASE WINDOW (Standard Recency) ---
        if let airDate = item.cachedNextAiringDate ?? item.releaseDate {
            let timeToAir = airDate.timeIntervalSince(now)

            // NEW: Released within last 14 days
            if timeToAir <= 0 && timeToAir >= -1209600 {
                return BadgeResult(label: "NEW", isSparkle: true)
            }

            // SOON: Releasing within next 48 hours
            if timeToAir > 0 && timeToAir <= 172800 {
                return BadgeResult(label: "SOON", isSparkle: false)
            }
        }

        // --- LEVEL 3: USER ENGAGEMENT (Behavioral & Backlog Nudges) ---
        if item.type == .tvShow, let tv = item.tvShowDetails {
            // 1. BEHAVIORAL BINGE (New: User is actively binging right now)
            if recentlyWatchedCount >= 3 {
                return BadgeResult(label: "BINGE", isSparkle: true)
            }

            // Rely on pre-calculated remainingEpisodesCount to avoid recalculating unwatchedAiredCount fully
            let remainingCount = tv.remainingEpisodesCount ?? 0
            
            let isLikedOrLoved = item.taste == .like || item.taste == .love

            // 2. CATCH UP (Selective Nudge)
            if isLikedOrLoved, let nextAiring = item.cachedNextAiringDate {
                let daysToAiring = nextAiring.timeIntervalSince(now) / 86400
                if daysToAiring > 0 && daysToAiring <= 7 && remainingCount > 0 {
                    return BadgeResult(label: "CATCH UP", isSparkle: false)
                }
            }

            // 3. BACKLOG BINGE (Legacy: High progress + backlog)
            if remainingCount > 0 && isLikedOrLoved {
                let totalEpisodes = tv.totalEpisodesCount
                let watchedEpisodes = tv.watchedEpisodesCount
                let progress = totalEpisodes > 0 ? Double(watchedEpisodes) / Double(totalEpisodes) : 0
                
                if progress >= 0.20 {
                    return BadgeResult(label: "BINGE", isSparkle: false)
                }
            }
        }

        // --- LEVEL 4: PASSIVE FALLBACK ---
        if let release = item.releaseDate {
            let timeToRelease = release.timeIntervalSince(now)
            if timeToRelease <= 0 && timeToRelease > -604800 * 2 { // Last 14 days
                return BadgeResult(label: "RECENT", isSparkle: false)
            }
        }

        return nil
    }
}
