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

        // --- LEVEL 1: MILESTONE EVENTS (Highest Priority) ---
        // These are checked against the user's NEXT unwatched episode to ensure relevance.
        if item.type == .tvShow, let tv = item.tvShowDetails {
            // Find the first unwatched episode in aired order
            let unwatchedAired = tv.seasons.flatMap { $0.episodes }
                .filter { !$0.isWatched && ($0.airDateAsDate ?? .distantFuture) <= now.addingTimeInterval(86400) } // Include next 24h for imminent premieres
                .sorted {
                    if $0.seasonNumber != $1.seasonNumber {
                        return $0.seasonNumber < $1.seasonNumber
                    }
                    return $0.episodeNumber < $1.episodeNumber
                }
            
            if let nextToWatch = unwatchedAired.first, let airDate = nextToWatch.airDateAsDate {
                let daysSinceAir = now.timeIntervalSince(airDate) / 86400
                let isVeryRecent = daysSinceAir >= -1 && daysSinceAir <= 7 // Within last 7 days or next 24h
                
                if isVeryRecent {
                    // 1. SEASON/SERIES PREMIERE
                    // Only show if this is the first episode of a season AND the user is actually at this season.
                    if nextToWatch.episodeNumber == 1 {
                        let label = nextToWatch.seasonNumber == 1 ? "SERIES PREMIERE" : "SEASON PREMIERE"
                        let icon = nextToWatch.seasonNumber == 1 ? "star.square.fill" : "play.square.stack.fill"
                        return BadgeResult(label: label, icon: icon, isSparkle: true)
                    }
                    
                    // 2. FINALE
                    // Only show if this is the last episode of the season the user is currently watching.
                    if let season = nextToWatch.season, nextToWatch.episodeNumber == season.episodeCount {
                        return BadgeResult(label: "FINALE", icon: "flag.checkered", isSparkle: true)
                    }
                    
                    // 3. BINGE DROP (Multiple episodes aired on same recent day for the user's current progress)
                    let airedOnSameDay = unwatchedAired.filter { $0.airDate == nextToWatch.airDate }
                    if airedOnSameDay.count > 1 {
                        return BadgeResult(label: "BINGE DROP", icon: "sparkles.tv", isSparkle: true)
                    }
                }
            }
        }

        // --- LEVEL 2: RELEASE WINDOW (Standard Recency) ---
        if let airDate = item.cachedNextAiringDate ?? item.releaseDate {
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

        // --- LEVEL 3: USER ENGAGEMENT (Backlog Nudges) ---
        if item.type == .tvShow, let tv = item.tvShowDetails {
            let unwatchedAiredCount = tv.seasons.flatMap { $0.episodes }
                .filter { !$0.isWatched && ($0.airDateAsDate ?? .distantFuture) <= now }
                .count
            
            let isLikedOrLoved = item.taste == .like || item.taste == .love

            // 1. CATCH UP (Selective Nudge)
            // Requirements:
            // - Show is marked as "Like" or "Love"
            // - A new episode/season is airing VERY soon (next 7 days)
            // - User has an active backlog to clear before that date
            if isLikedOrLoved, let nextAiring = item.cachedNextAiringDate {
                let daysToAiring = nextAiring.timeIntervalSinceNow / 86400
                if daysToAiring > 0 && daysToAiring <= 7 && unwatchedAiredCount > 0 {
                    return BadgeResult(label: "CATCH UP", icon: "arrow.uturn.right.circle.fill", isSparkle: false)
                }
            }

            // 2. BINGE (User commitment nudge)
            // Requirements: 
            // - User has watched at least 20% of the show
            // - Show is marked as "Like" or "Love"
            // - User has an active backlog (any count)
            if unwatchedAiredCount > 0 && isLikedOrLoved {
                let totalEpisodes = tv.totalEpisodesCount
                let watchedEpisodes = tv.watchedEpisodesCount
                let progress = totalEpisodes > 0 ? Double(watchedEpisodes) / Double(totalEpisodes) : 0
                
                if progress >= 0.20 {
                    return BadgeResult(label: "BINGE", icon: "play.square.stack.fill", isSparkle: false)
                }
            }
        }

        // --- LEVEL 4: PASSIVE FALLBACK ---
        if let release = item.releaseDate {
            let timeToRelease = release.timeIntervalSinceNow
            if timeToRelease <= 0 && timeToRelease > -604800 * 2 { // Last 14 days
                return BadgeResult(label: "RECENT", icon: "star.fill", isSparkle: false)
            }
        }

        return nil
    }
}
