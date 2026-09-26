import Foundation
import SwiftData

@Model
final class TVEpisode {
    var episodeNumber: Int
    var seasonNumber: Int
    var name: String
    var overview: String
    var airDate: String? {
        didSet {
            guard !isUpdatingAirDateValue else { return }
            updateAirDateValue()
        }
    }
    var airstamp: String? {
        didSet {
            guard !isUpdatingAirDateValue else { return }
            updateAirDateValue()
        }
    }
    var airDateValue: Date?
    private var isUpdatingAirDateValue = false
    @Transient private var _cachedAirDateAsDate: Date?
    @Transient private var _airDateAsDateComputed = false
    var runtime: Int?
    var isWatched: Bool = false
    var lastWatchedDate: Date?
    var watchedDate: Date?
    /// Earliest date this episode was ever watched. Durable: it survives
    /// rewatch projection resets and bulk "mark all watched", so the original
    /// first-watch date is never overwritten by a later occurrence.
    /// Per-occurrence history lives in `WatchEvent`.
    var firstWatchedDate: Date?
    var showID: Int?
    @Attribute(.unique) var uniqueID: String? = nil
    var season: TVSeason?

    func markWatched(_ watched: Bool, recordHistory: Bool = true) {
        guard self.isWatched != watched else { return }
        applyWatchedState(
            watched,
            date: watched ? Date() : nil,
            updatesInteractionDate: true
        )
        if recordHistory {
            scheduleWatchHistoryMutation(watched: watched)
        }
    }

    func applyImportedWatchState(watchedAt: Date?) {
        if isWatched {
            if let watchedAt {
                lastWatchedDate = watchedAt
                self.watchedDate = watchedAt
                recordFirstWatch(importedAt: watchedAt)
            }
            return
        }
        applyWatchedState(true, date: watchedAt, updatesInteractionDate: false)
    }

    func restoreWatchedProjection(from date: Date?) {
        guard !isWatched else { return }
        applyWatchedState(true, date: date, updatesInteractionDate: false)
    }

    /// First-watch date for display, tolerating rows that predate the field.
    var firstKnownWatchDate: Date? {
        firstWatchedDate ?? watchedDate ?? lastWatchedDate
    }

    /// True while the owning show is in a rewatch cycle. During a rewatch the
    /// current occurrence is *not* the first watch, so the durable date must come
    /// from the ledger rather than from this event.
    private var isInRewatchCycle: Bool {
        season?.tvShowDetails?.item?.state == .rewatching
    }

    private func recordFirstWatch(importedAt date: Date) {
        if let existing = firstWatchedDate {
            // An import can carry an earlier date than what we already hold
            // (e.g. restoring a backup) — keep the true minimum.
            if date < existing { firstWatchedDate = date }
        } else if !isInRewatchCycle {
            firstWatchedDate = date
        }
    }

    func applyWatchedState(_ watched: Bool, date: Date?, updatesInteractionDate: Bool) {
        self.isWatched = watched
        if watched {
            self.lastWatchedDate = date
            self.watchedDate = date
            // Occurrence dates are monotonically later occurrences, so the minimum
            // is always the first watch. Rewatches never move this date.
            if let date { recordFirstWatch(importedAt: date) }
        } else {
            // Only the current projection is cleared. `firstWatchedDate` is
            // intentionally preserved: unwatching is a projection edit, not a
            // history deletion.
            self.lastWatchedDate = nil
            self.watchedDate = nil
        }

        let delta = watched ? 1 : -1
        season?.watchedEpisodesCount += delta

        if let tv = season?.tvShowDetails {
            if season?.seasonNumber ?? 0 > 0 {
                tv.watchedEpisodesCount += delta
            }

            if let item = tv.item {
                let epRuntime = self.runtime ?? 0
                let currentRuntime = item.cachedRuntime ?? 0
                item.cachedRuntime = max(0, currentRuntime + (watched ? epRuntime : -epRuntime))
                if watched && updatesInteractionDate {
                    item.lastInteractionDate = Date()
                }
            }

            let now = Date()
            if let airDate = airDateValue, airDate <= now {
                let oldRemaining = tv.remainingEpisodesCount ?? 0
                tv.remainingEpisodesCount = max(0, oldRemaining - delta)
            }
        }
    }

    private func scheduleWatchHistoryMutation(watched: Bool) {
        guard modelContext != nil,
              let mediaID = season?.tvShowDetails?.item?.id ?? showID.map({ "tv_\($0)" }) else { return }
        let episodeID = uniqueID ?? "\(mediaID)_\(seasonNumber)_\(episodeNumber)"
        let watchedAt = watchedDate ?? lastWatchedDate ?? Date()
        let runtimeMinutes = runtime

        Task { @MainActor in
            guard let container = DataService.modelContainer else { return }
            let context = container.mainContext
            WatchHistoryCoordinator.recordEpisodeMutation(
                mediaID: mediaID,
                episodeID: episodeID,
                watchedAt: watchedAt,
                runtimeMinutes: runtimeMinutes,
                isWatched: watched,
                context: context
            )
            SaveCoordinator.shared.requestSave(context)
        }
    }
    
    // UI property: Uses the persistent airDateValue if accurate, or recalculates (cached after first access)
    var airDateAsDate: Date? {
        if let airDateValue { return airDateValue }
        if _airDateAsDateComputed { return _cachedAirDateAsDate }
        let result = DateUtils.parseEpisodeDate(
            airDate, 
            time: nil, 
            airstamp: airstamp, 
            timezone: season?.tvShowDetails?.timezone, 
            serviceName: season?.tvShowDetails?.network ?? season?.tvShowDetails?.item?.cachedNetwork, 
            for: season?.tvShowDetails
        )
        _cachedAirDateAsDate = result
        _airDateAsDateComputed = true
        return result
    }

    func updateAirDateValue() {
        isUpdatingAirDateValue = true
        defer { isUpdatingAirDateValue = false }
        
        let oldValue = airDateValue
        if let parsed = DateUtils.parseEpisodeDate(
            airDate,
            time: nil,
            airstamp: airstamp,
            timezone: season?.tvShowDetails?.timezone,
            serviceName: season?.tvShowDetails?.network ?? season?.tvShowDetails?.item?.cachedNetwork,
            for: season?.tvShowDetails
        ) {
            self.airDateValue = parsed
        }
        _airDateAsDateComputed = false
        _cachedAirDateAsDate = nil
        if oldValue != airDateValue, let pid = season?.tvShowDetails?.item?.persistentModelID {
            BadgeEngine.invalidateScan(for: pid)
        }
    }
    
    init(episodeNumber: Int, seasonNumber: Int, name: String, overview: String, airDate: String? = nil, airstamp: String? = nil, runtime: Int? = nil, isWatched: Bool = false, showID: Int? = nil) {
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.airDate = airDate
        self.airstamp = airstamp
        self.runtime = runtime
        self.isWatched = isWatched
        self.showID = showID
        if let showID = showID {
            self.uniqueID = "\(showID)_\(seasonNumber)_\(episodeNumber)"
        } else {
            self.uniqueID = UUID().uuidString
        }
        // Note: airDateValue may still be 00:00 here if network is unknown during init.
        // It gets healed by MaintenanceService or recalculated by airDateAsDate property.
    }
}
