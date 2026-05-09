import Foundation

// MARK: - Badge Logic Engine
/// Centralized engine for calculating semantic badges for Movies and TV Shows.
struct BadgeEngine {
    struct BadgeResult: Equatable {
        let label: String
        let icon: String
        let isSparkle: Bool
    }

    static func calculateBadge(for item: MediaItem, now: Date = Date()) -> BadgeResult? {
        // --- LEVEL 1: MILESTONE EVENTS (Highest Priority) ---
        // These are checked against the user's NEXT unwatched episode to ensure relevance.
        if item.type == .tvShow, let tv = item.tvShowDetails {
            // Find the absolute next unwatched episode regardless of date
            let unwatchedEpisodes = tv.seasons.flatMap { $0.episodes }
                .filter { !$0.isWatched }
                .sorted {
                    if $0.seasonNumber != $1.seasonNumber {
                        return $0.seasonNumber < $1.seasonNumber
                    }
                    return $0.episodeNumber < $1.episodeNumber
                }
            
            if let nextToWatch = unwatchedEpisodes.first {
                // Check for FINALE first - can show even for future releases
                if let season = nextToWatch.season, nextToWatch.episodeNumber == season.episodeCount {
                    return BadgeResult(label: "FINALE", icon: "flag.checkered", isSparkle: true)
                }

                if let airDate = nextToWatch.airDateAsDate {
                    let daysSinceAir = now.timeIntervalSince(airDate) / 86400
                    // Milestone window: Within last 7 days or next 14 days (widened for hype)
                    let isRelevantMilestone = daysSinceAir >= -14 && daysSinceAir <= 7
                    
                    if isRelevantMilestone {
                        // 1. SEASON/SERIES PREMIERE
                        if nextToWatch.episodeNumber == 1 {
                            let label = nextToWatch.seasonNumber == 1 ? "SERIES PREMIERE" : "SEASON PREMIERE"
                            let icon = nextToWatch.seasonNumber == 1 ? "star.square.fill" : "play.square.stack.fill"
                            return BadgeResult(label: label, icon: icon, isSparkle: true)
                        }
                        
                        // 3. BINGE DROP (Multiple episodes aired on same day for the user's current progress)
                        let airedOnSameDay = unwatchedEpisodes.filter { $0.airDate == nextToWatch.airDate }
                        if airedOnSameDay.count > 1 {
                            return BadgeResult(label: "BINGE DROP", icon: "sparkles.tv", isSparkle: true)
                        }
                    }
                }
            }
        }

        // --- LEVEL 2: RELEASE WINDOW (Standard Recency) ---
        if let airDate = item.cachedNextAiringDate ?? item.releaseDate {
            let timeToAir = airDate.timeIntervalSince(now)

            // NEW: Released within last 48 hours
            if timeToAir <= 0 && timeToAir >= -172800 {
                return BadgeResult(label: "NEW", icon: "sparkles", isSparkle: true)
            }

            // SOON: Releasing within next 48 hours
            if timeToAir > 0 && timeToAir <= 172800 {
                return BadgeResult(label: "SOON", icon: "clock.badge.fill", isSparkle: false)
            }
        }

        // --- LEVEL 3: USER ENGAGEMENT (Behavioral & Backlog Nudges) ---
        if item.type == .tvShow, let tv = item.tvShowDetails {
            let allEpisodes = tv.seasons.flatMap { $0.episodes }
            
            // 1. BEHAVIORAL BINGE (New: User is actively binging right now)
            let fortyEightHoursAgo = now.addingTimeInterval(-172800)
            let recentlyWatchedCount = allEpisodes.filter { 
                $0.isWatched && ($0.lastWatchedDate ?? .distantPast) >= fortyEightHoursAgo 
            }.count
            
            if recentlyWatchedCount >= 3 {
                return BadgeResult(label: "BINGE", icon: "flame.fill", isSparkle: true)
            }

            let unwatchedAiredCount = allEpisodes
                .filter { !$0.isWatched && ($0.airDateAsDate ?? .distantFuture) <= now }
                .count
            
            let isLikedOrLoved = item.taste == .like || item.taste == .love

            // 2. CATCH UP (Selective Nudge)
            if isLikedOrLoved, let nextAiring = item.cachedNextAiringDate {
                let daysToAiring = nextAiring.timeIntervalSince(now) / 86400
                if daysToAiring > 0 && daysToAiring <= 7 && unwatchedAiredCount > 0 {
                    return BadgeResult(label: "CATCH UP", icon: "arrow.uturn.right.circle.fill", isSparkle: false)
                }
            }

            // 3. BACKLOG BINGE (Legacy: High progress + backlog)
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
            let timeToRelease = release.timeIntervalSince(now)
            if timeToRelease <= 0 && timeToRelease > -604800 * 2 { // Last 14 days
                return BadgeResult(label: "RECENT", icon: "star.fill", isSparkle: false)
            }
        }

        return nil
    }
}
