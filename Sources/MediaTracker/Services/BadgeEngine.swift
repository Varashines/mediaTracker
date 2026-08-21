import Foundation
import SwiftData
import os

// MARK: - Smart Badge Identifier

enum SmartBadge: String, CaseIterable, Sendable {
    case premiere = "PREMIERE"
    case finale = "FINALE"
    case bingeDrop = "BINGE DROP"
    case binge = "BINGE"
    case behind = "BEHIND"
    case new = "NEW"
    case soon = "SOON"
    case hooked = "HOOKED"

    static let radarBadges: Set<SmartBadge> = [.new, .bingeDrop, .premiere, .finale, .hooked]
    static let recentBadges: Set<SmartBadge> = [.new, .bingeDrop, .finale, .premiere, .hooked]
}

// MARK: - Badge Logic Engine

struct BadgeEngine {
    struct BadgeResult: Equatable {
        let label: SmartBadge
        let isSparkle: Bool
    }

    private static let recentlyWatchedCutoff: TimeInterval = -TimeInterval.days2
    /// Movies, like TV season premieres, stay on the premiere radar until release.
    private static let moviePremiereWindow: ClosedRange<TimeInterval> = -TimeInterval.days3...Double.greatestFiniteMagnitude
    private static let newBadgeWindow: ClosedRange<TimeInterval> = -1209600...0
    private static let soonBadgeWindow: ClosedRange<TimeInterval> = 0...TimeInterval.days2
    private static let premiereDaysWindow: ClosedRange<Double> = -Double.greatestFiniteMagnitude...3
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

    private struct CachedEpisodeScan: Sendable {
        let scan: EpisodeScan
        let expiresAt: Date
    }

    /// Cache episode scans per show to avoid re-iterating all seasons/episodes on every badge call.
    /// A short expiry keeps time-sensitive engagement signals, such as HOOKED,
    /// accurate even if no episode state changes occur.
    private static let episodeScanCacheLifetime = TimeInterval.secondsInHour / 2
    private static let episodeScanCache = OSAllocatedUnfairLock<[PersistentIdentifier: CachedEpisodeScan]>(uncheckedState: [:])

    nonisolated static func invalidateScan(for showID: PersistentIdentifier) {
        _ = episodeScanCache.withLock { $0.removeValue(forKey: showID) }
    }

    nonisolated static func clearScanCache() {
        episodeScanCache.withLock { $0.removeAll() }
    }

    nonisolated private static func readScanCache(_ showID: PersistentIdentifier, now: Date) -> EpisodeScan? {
        episodeScanCache.withLock { cache in
            guard let cached = cache[showID] else { return nil }
            guard cached.expiresAt > now else {
                cache.removeValue(forKey: showID)
                return nil
            }
            return cached.scan
        }
    }

    nonisolated private static func writeScanCache(_ showID: PersistentIdentifier, scan: EpisodeScan, now: Date) {
        episodeScanCache.withLock {
            $0[showID] = CachedEpisodeScan(
                scan: scan,
                expiresAt: now.addingTimeInterval(episodeScanCacheLifetime)
            )
        }
    }

    static func calculateBadge(for item: MediaItem, now: Date = Date()) -> BadgeResult? {
        guard item.state != .dropped else { return nil }

        let scan: EpisodeScan
        if item.type == .tvShow {
            let pid = item.persistentModelID
            if let cached = readScanCache(pid, now: now) {
                scan = cached
            } else {
                scan = scanEpisodes(for: item, now: now)
                writeScanCache(pid, scan: scan, now: now)
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
        let cutoff = now.addingTimeInterval(recentlyWatchedCutoff)

        // Batch fetch all episodes for this show to avoid N+1 relationship faults
        let batchResult = batchScan(tv: tv, now: now, cutoff: cutoff)
        if let result = batchResult { return result }

        // Fallback: relationship traversal (for contexts where showID isn't set, e.g., tests)
        return relationshipScan(tv: tv, now: now, cutoff: cutoff)
    }

    private static func batchScan(tv: TVShowDetails, now: Date, cutoff: Date) -> EpisodeScan? {
        guard let context = tv.modelContext else { return nil }
        let tmdbID = tv.tmdbID
        var eDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.showID == tmdbID })
        eDescriptor.propertiesToFetch = [\.isWatched, \.seasonNumber, \.episodeNumber, \.airDateValue, \.lastWatchedDate, \.uniqueID]
        guard let allEpisodes = try? context.fetch(eDescriptor), !allEpisodes.isEmpty else { return nil }

        var nextEpisodeNumber = 0
        var nextSeasonEpisodeCount = 0
        var nextAirDate: Date? = nil
        var airedOnSameDayCount = 0
        var recentlyWatchedCount = 0
        var foundNext = false

        var episodeMap: [Int: [TVEpisode]] = [:]
        for ep in allEpisodes {
            episodeMap[ep.seasonNumber, default: []].append(ep)
        }

        for season in tv.seasons.liveModels.sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
            guard season.seasonNumber > 0 else { continue }
            guard let seasonEpisodes = episodeMap[season.seasonNumber] else { continue }
            for ep in seasonEpisodes.sorted(by: { $0.episodeNumber < $1.episodeNumber }) {
                if !ep.isWatched {
                    if !foundNext {
                        nextEpisodeNumber = ep.episodeNumber
                        nextSeasonEpisodeCount = season.episodeCount
                        nextAirDate = ep.airDateAsDate
                        foundNext = true
                        airedOnSameDayCount = 1
                    } else if let epDate = ep.airDateAsDate, let next = nextAirDate,
                              Calendar.current.isDate(epDate, inSameDayAs: next) {
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

    private static func relationshipScan(tv: TVShowDetails, now: Date, cutoff: Date) -> EpisodeScan {
        var nextEpisodeNumber = 0
        var nextSeasonEpisodeCount = 0
        var nextAirDate: Date? = nil
        var airedOnSameDayCount = 0
        var recentlyWatchedCount = 0
        var foundNext = false

        for season in tv.seasons.liveModels.sorted(by: { $0.seasonNumber < $1.seasonNumber }) {
            guard season.seasonNumber > 0 else { continue }
            for ep in season.episodes.liveModels.sorted(by: { $0.episodeNumber < $1.episodeNumber }) {
                if !ep.isWatched {
                    if !foundNext {
                        nextEpisodeNumber = ep.episodeNumber
                        nextSeasonEpisodeCount = ep.season?.episodeCount ?? 0
                        nextAirDate = ep.airDateAsDate
                        foundNext = true
                        airedOnSameDayCount = 1
                    } else if let epDate = ep.airDateAsDate, let next = nextAirDate,
                              Calendar.current.isDate(epDate, inSameDayAs: next) {
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
            return BadgeResult(label: .hooked, isSparkle: true)
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

// MARK: - Badge Change Delta Buffer

/// Thread-safe accumulator for badge count changes.
/// Coalesces individual badge changes during bulk operations so they can be
/// flushed as a single write transaction, eliminating N detached ModelActor tasks.
private final class BadgeDeltaStore: @unchecked Sendable {
    private var deltas: [String: Int] = [:]
    private let lock = OSAllocatedUnfairLock(uncheckedState: ())

    func enqueue(old: String?, new: String?) {
        lock.withLockUnchecked {
            if let old, !old.isEmpty {
                deltas[old, default: 0] -= 1
                if deltas[old] == 0 { deltas.removeValue(forKey: old) }
            }
            if let new, !new.isEmpty {
                deltas[new, default: 0] += 1
                if deltas[new] == 0 { deltas.removeValue(forKey: new) }
            }
        }
    }

    func takeSnapshot() -> [String: Int] {
        lock.withLockUnchecked {
            let snapshot = deltas
            deltas = [:]
            return snapshot
        }
    }
}

private actor BadgeDeltaFlushCoordinator {
    static let shared = BadgeDeltaFlushCoordinator()

    private var pendingFlush: Task<Void, Never>?

    func schedule(container: ModelContainer) {
        pendingFlush?.cancel()
        pendingFlush = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await BadgeEngine.flushBadgeChanges(container: container)
        }
    }
}

extension BadgeEngine {
    private static let badgeDeltaStore = BadgeDeltaStore()

    /// Enqueue a badge change for batched delivery.
    /// Thread-safe — can be called from any context without awaiting.
    nonisolated static func enqueueBadgeChange(old: String?, new: String?) {
        badgeDeltaStore.enqueue(old: old, new: new)
    }

    /// Debounces aggregate badge-count updates for individual interactions.
    /// Bulk paths still flush directly after their transaction completes.
    static func scheduleBadgeDeltaFlush(container: ModelContainer) {
        Task {
            await BadgeDeltaFlushCoordinator.shared.schedule(container: container)
        }
    }

    /// Flush all accumulated badge deltas to the database in a single transaction.
    /// Call this before `context.save()` after any bulk operation that may have
    /// changed badges (heal, refresh, mark-all-watched, stale badge refresh).
    static func flushBadgeChanges(container: ModelContainer) async {
        let deltas = badgeDeltaStore.takeSnapshot()
        guard !deltas.isEmpty else { return }
        let sync = DiscoverySyncService(modelContainer: container)
        await sync.applyBadgeDeltas(deltas)
    }
}
