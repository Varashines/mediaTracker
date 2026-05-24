import Foundation

// MARK: - Smart Badge Identifier

enum SmartBadge: String, CaseIterable, Sendable {
    case premiere = "PREMIERE"
    case finale = "FINALE"
    case bingeDrop = "BINGE DROP"
    case binge = "BINGE"
    case behind = "BEHIND"
    case catchUp = "CATCH UP"
    case new = "NEW"
    case soon = "SOON"
    case recent = "RECENT"
}

// MARK: - Badge Logic Engine

struct BadgeEngine {
    struct BadgeResult: Equatable {
        let label: SmartBadge
        let isSparkle: Bool
    }

    /// Pre-computed episode scan data — extracted to a single pass.
    private struct EpisodeScan: Equatable, Sendable {
        let nextEpisodeNumber: Int
        let nextSeasonEpisodeCount: Int
        let nextAirDate: Date?
        let airedOnSameDayCount: Int
        let recentlyWatchedCount: Int

        static let empty = EpisodeScan(nextEpisodeNumber: 0, nextSeasonEpisodeCount: 0, nextAirDate: nil, airedOnSameDayCount: 0, recentlyWatchedCount: 0)
    }

    static func calculateBadge(for item: MediaItem, now: Date = Date()) -> BadgeResult? {
        guard item.state != .dropped else { return nil }

        let scan = item.type == .tvShow ? scanEpisodes(for: item, now: now) : .empty

        if let result = milestoneBadge(for: item, scan: scan, now: now) { return result }
        if let result = releaseWindowBadge(for: item, now: now) { return result }
        if let result = engagementBadge(for: item, scan: scan, now: now) { return result }
        return nil
    }

    // MARK: - Episode Scan (single pass)

    private static func scanEpisodes(for item: MediaItem, now: Date) -> EpisodeScan {
        guard let tv = item.tvShowDetails else { return .empty }

        var nextEpisodeNumber = 0
        var nextSeasonEpisodeCount = 0
        var nextAirDate: Date? = nil
        var airedOnSameDayCount = 0
        var recentlyWatchedCount = 0
        let cutoff = now.addingTimeInterval(-172800)
        var foundNext = false

        for season in tv.seasons.filter({ !$0.isDeleted && $0.modelContext != nil }).sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
            for ep in season.episodes.filter({ !$0.isDeleted && $0.modelContext != nil }).sorted(by: { $0.episodeNumber < $1.episodeNumber }) {
                if !ep.isWatched {
                    if !foundNext {
                        nextEpisodeNumber = ep.episodeNumber
                        nextSeasonEpisodeCount = ep.season?.episodeCount ?? 0
                        nextAirDate = ep.airDateAsDate
                        foundNext = true
                        airedOnSameDayCount = 1
                    } else if ep.airDateAsDate == nextAirDate {
                        airedOnSameDayCount += 1
                    }
                } else if let lastWatched = ep.lastWatchedDate, lastWatched >= cutoff {
                    recentlyWatchedCount += 1
                }
            }
        }

        return EpisodeScan(
            nextEpisodeNumber: nextEpisodeNumber,
            nextSeasonEpisodeCount: nextSeasonEpisodeCount,
            nextAirDate: nextAirDate,
            airedOnSameDayCount: airedOnSameDayCount,
            recentlyWatchedCount: recentlyWatchedCount
        )
    }

    // MARK: - Pipeline Stages

    private static func milestoneBadge(for item: MediaItem, scan: EpisodeScan, now: Date) -> BadgeResult? {
        guard let airDate = scan.nextAirDate else { return nil }
        let daysSinceAir = now.timeIntervalSince(airDate) / 86400

        if scan.nextEpisodeNumber == 1 && daysSinceAir <= 3 && daysSinceAir >= -30 {
            return BadgeResult(label: .premiere, isSparkle: true)
        }

        let inMilestoneWindow = daysSinceAir >= -14 && daysSinceAir <= 14

        if scan.nextEpisodeNumber == scan.nextSeasonEpisodeCount && scan.nextSeasonEpisodeCount > 0,
           daysSinceAir >= -7 && daysSinceAir <= 14 {
            return BadgeResult(label: .finale, isSparkle: true)
        }

        if inMilestoneWindow && scan.airedOnSameDayCount > 1 {
            return BadgeResult(label: .bingeDrop, isSparkle: true)
        }

        return nil
    }

    private static func releaseWindowBadge(for item: MediaItem, now: Date) -> BadgeResult? {
        guard let airDate = item.cachedNextAiringDate ?? item.releaseDate else { return nil }
        let timeToAir = airDate.timeIntervalSince(now)

        if item.type == .movie && timeToAir >= -259200 && timeToAir <= 2592000 {
            return BadgeResult(label: .premiere, isSparkle: true)
        }
        if timeToAir <= 0 && timeToAir >= -1209600 {
            return BadgeResult(label: .new, isSparkle: true)
        }
        if timeToAir > 0 && timeToAir <= 172800 {
            return BadgeResult(label: .soon, isSparkle: false)
        }
        return nil
    }

    private static func engagementBadge(for item: MediaItem, scan: EpisodeScan, now: Date) -> BadgeResult? {
        guard item.type == .tvShow, let tv = item.tvShowDetails else { return nil }
        let remainingCount = tv.remainingEpisodesCount ?? 0
        guard remainingCount > 0 else { return nil }

        if scan.recentlyWatchedCount >= 3 {
            return BadgeResult(label: .binge, isSparkle: true)
        }

        let isLikedOrLoved = item.taste == .like || item.taste == .love
        guard isLikedOrLoved else { return nil }

        if let nextAiring = item.cachedNextAiringDate {
            let daysToAiring = nextAiring.timeIntervalSince(now) / 86400
            if daysToAiring > 0 && daysToAiring <= 7 {
                return BadgeResult(label: .behind, isSparkle: false)
            }
        }

        let total = tv.totalEpisodesCount
        let watched = tv.watchedEpisodesCount
        if total > 0, Double(watched) / Double(total) >= 0.20 {
            return BadgeResult(label: .binge, isSparkle: false)
        }

        return nil
    }
}
