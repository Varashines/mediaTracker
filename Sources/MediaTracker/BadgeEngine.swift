import Foundation
import SwiftData

// MARK: - Smart Badge Identifier

enum SmartBadge: String, CaseIterable, Sendable {
    case premiere = "PREMIERE"
    case finale = "FINALE"
    case bingeDrop = "BINGE DROP"
    case binge = "BINGE"
    case behind = "BEHIND"
    case new = "NEW"
    case soon = "SOON"

    static let radarBadges: Set<SmartBadge> = [.new, .bingeDrop, .premiere, .finale]
    static let recentBadges: Set<SmartBadge> = [.new, .bingeDrop, .finale, .premiere]
}

// MARK: - Badge Logic Engine

struct BadgeEngine {
    struct BadgeResult: Equatable {
        let label: SmartBadge
        let isSparkle: Bool
    }

    private static let recentlyWatchedCutoff: TimeInterval = -172800
    private static let moviePremiereWindow: ClosedRange<TimeInterval> = -259200...2592000
    private static let newBadgeWindow: ClosedRange<TimeInterval> = -1209600...0
    private static let soonBadgeWindow: ClosedRange<TimeInterval> = 0...172800
    private static let premiereDaysWindow: ClosedRange<Double> = -30...3
    private static let finaleDaysWindow: ClosedRange<Double> = -7...14
    private static let milestoneDaysWindow: ClosedRange<Double> = -14...14
    private static let behindWindowDays: Double = 7
    private static let bingeEngagementThreshold: Int = 3
    private static let bingeProgressThreshold: Double = 0.20

    /// Pre-computed episode scan data — extracted to a single pass.
    private struct EpisodeScan: Equatable, Sendable {
        let nextEpisodeNumber: Int
        let nextSeasonEpisodeCount: Int
        let nextAirDate: Date?
        let airedOnSameDayCount: Int
        let recentlyWatchedCount: Int

        static let empty = EpisodeScan(nextEpisodeNumber: 0, nextSeasonEpisodeCount: 0, nextAirDate: nil, airedOnSameDayCount: 0, recentlyWatchedCount: 0)
    }

    /// Cache episode scans per show to avoid re-iterating all seasons/episodes on every badge call.
    /// Cleared on episode state changes (see MediaItem.syncCachedProperties).
    nonisolated(unsafe) private static var scanCacheLock = os_unfair_lock()
    nonisolated(unsafe) private static var episodeScanCache: [PersistentIdentifier: EpisodeScan] = [:]

    nonisolated static func invalidateScan(for showID: PersistentIdentifier) {
        os_unfair_lock_lock(&scanCacheLock)
        episodeScanCache.removeValue(forKey: showID)
        os_unfair_lock_unlock(&scanCacheLock)
    }

    nonisolated static func clearScanCache() {
        os_unfair_lock_lock(&scanCacheLock)
        episodeScanCache.removeAll()
        os_unfair_lock_unlock(&scanCacheLock)
    }

    nonisolated private static func readScanCache(_ showID: PersistentIdentifier) -> EpisodeScan? {
        os_unfair_lock_lock(&scanCacheLock)
        let result = episodeScanCache[showID]
        os_unfair_lock_unlock(&scanCacheLock)
        return result
    }

    nonisolated private static func writeScanCache(_ showID: PersistentIdentifier, scan: EpisodeScan) {
        os_unfair_lock_lock(&scanCacheLock)
        episodeScanCache[showID] = scan
        os_unfair_lock_unlock(&scanCacheLock)
    }

    static func calculateBadge(for item: MediaItem, now: Date = Date()) -> BadgeResult? {
        guard item.state != .dropped else { return nil }

        let scan: EpisodeScan
        if item.type == .tvShow {
            let pid = item.persistentModelID
            if let cached = readScanCache(pid) {
                scan = cached
            } else {
                scan = scanEpisodes(for: item, now: now)
                writeScanCache(pid, scan: scan)
            }
        } else {
            scan = .empty
        }

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
        let cutoff = now.addingTimeInterval(recentlyWatchedCutoff)
        var foundNext = false

        for season in tv.seasons.liveModels.sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
            for ep in season.episodes.liveModels.sorted(by: { $0.episodeNumber < $1.episodeNumber }) {
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
        let daysSinceAir = now.timeIntervalSince(airDate) / .secondsInDay

        if scan.nextEpisodeNumber == 1 && premiereDaysWindow.contains(daysSinceAir) {
            return BadgeResult(label: .premiere, isSparkle: true)
        }

        let inMilestoneWindow = milestoneDaysWindow.contains(daysSinceAir)

        if scan.nextEpisodeNumber == scan.nextSeasonEpisodeCount && scan.nextSeasonEpisodeCount > 0,
           finaleDaysWindow.contains(daysSinceAir) {
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

        if item.type == .movie && moviePremiereWindow.contains(timeToAir) {
            return BadgeResult(label: .premiere, isSparkle: true)
        }
        if newBadgeWindow.contains(timeToAir) {
            return BadgeResult(label: .new, isSparkle: true)
        }
        if soonBadgeWindow.contains(timeToAir) {
            return BadgeResult(label: .soon, isSparkle: false)
        }
        return nil
    }

    private static func engagementBadge(for item: MediaItem, scan: EpisodeScan, now: Date) -> BadgeResult? {
        guard item.type == .tvShow, let tv = item.tvShowDetails else { return nil }
        let remainingCount = tv.remainingEpisodesCount ?? 0
        guard remainingCount > 0 else { return nil }

        if scan.recentlyWatchedCount >= bingeEngagementThreshold {
            return BadgeResult(label: .binge, isSparkle: true)
        }

        let isLikedOrLoved = item.taste == .like || item.taste == .love
        guard isLikedOrLoved else { return nil }

        if let nextAiring = item.cachedNextAiringDate {
            let daysToAiring = nextAiring.timeIntervalSince(now) / .secondsInDay
            if daysToAiring > 0 && daysToAiring <= behindWindowDays {
                return BadgeResult(label: .behind, isSparkle: false)
            }
        }

        let total = tv.totalEpisodesCount
        let watched = tv.watchedEpisodesCount
        if total > 0, Double(watched) / Double(total) >= bingeProgressThreshold {
            return BadgeResult(label: .binge, isSparkle: false)
        }

        return nil
    }
}
