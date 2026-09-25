import Foundation
import SwiftData

enum WatchHistoryCoordinator {
    static func handleStateChange(
        item: MediaItem,
        from oldState: MediaState?,
        to newState: MediaState,
        context: ModelContext,
        now: Date = Date(),
        legacyCompletedAt: Date? = nil
    ) {
        guard item.modelContext != nil else { return }

        if newState == .rewatching, oldState != .rewatching {
            startRewatch(
                item: item,
                context: context,
                now: now,
                legacyCompletedAt: legacyCompletedAt
            )
            return
        }

        if newState == .completed, oldState == .rewatching {
            completeCurrentCycle(item: item, context: context, now: now, source: .manual)
            return
        }

        if newState == .completed, oldState != .completed, oldState != .rewatching {
            completeCurrentCycle(item: item, context: context, now: now, source: .manual)
        }
    }

    @discardableResult
    static func startRewatch(
        item: MediaItem,
        context: ModelContext,
        now: Date = Date(),
        legacyCompletedAt: Date? = nil
    ) -> WatchCycle {
        let kind = cycleKind(for: item)
        let current = currentCycle(for: item, context: context)

        if let current {
            let wasComplete = current.isComplete || current.state == .completed
            snapshotCurrentProgress(item: item, into: current, context: context, now: now, source: .manual)
            current.completedAt = current.completedAt ?? now
            current.isComplete = wasComplete
            current.state = .archived
        } else {
            let archived = WatchCycle(
                mediaID: item.id,
                kind: kind,
                startedAt: item.lastInteractionDate ?? now,
                completedAt: legacyCompletedAt ?? item.lastStateChangeDate ?? now,
                state: .archived,
                isBackfilled: true,
                isComplete: true
            )
            context.insert(archived)
            snapshotCurrentProgress(item: item, into: archived, context: context, now: now, source: .migration)
        }

        let next = WatchCycle(
            mediaID: item.id,
            kind: kind,
            startedAt: now,
            isRewatch: true,
            scopeEpisodeIDs: knownEpisodeIDs(for: item)
        )
        context.insert(next)
        item.rewatchCount += 1
        resetCurrentProjection(item: item)
        return next
    }

    @discardableResult
    static func resumePausedRewatch(
        item: MediaItem,
        context: ModelContext,
        now: Date = Date()
    ) -> WatchCycle? {
        guard item.type == .tvShow else { return nil }
        let mediaID = item.id
        let activeRaw = WatchCycleState.active.rawValue
        var activeDescriptor = FetchDescriptor<WatchCycle>(predicate: #Predicate {
            $0.mediaID == mediaID && $0.stateRaw == activeRaw
        })
        activeDescriptor.fetchLimit = 1
        guard (try? context.fetch(activeDescriptor).first) == nil else { return nil }

        let pausedRaw = WatchCycleState.paused.rawValue
        var pausedDescriptor = FetchDescriptor<WatchCycle>(
            predicate: #Predicate {
                $0.mediaID == mediaID && $0.stateRaw == pausedRaw && $0.isRewatch
            },
            sortBy: [SortDescriptor(\WatchCycle.startedAt, order: .reverse)]
        )
        pausedDescriptor.fetchLimit = 1
        guard let paused = try? context.fetch(pausedDescriptor).first else { return nil }

        paused.state = .active
        if let details = item.tvShowDetails {
            let scope = Set(paused.scopeEpisodeIDs)
            for season in details.seasons.liveModels {
                for episode in season.episodes.liveModels {
                    let episodeID = episode.uniqueID ?? "\(item.id)_\(season.seasonNumber)_\(episode.episodeNumber)"
                    guard scope.contains(episodeID) else { continue }
                    episode.markWatched(false, recordHistory: false)
                }
            }
            details.recalculateCachedProperties(triggerSync: false)
        }
        item.stateValue = MediaState.rewatching.rawValue
        item.lastInteractionDate = now
        item.lastStateChangeDate = now
        item.storedProgress = 0
        item.storedWatchProgressLabel = nil
        return paused
    }

    static func completeCurrentCycle(
        item: MediaItem,
        context: ModelContext,
        now: Date = Date(),
        source: WatchEventSource = .manual
    ) {
        let cycle = currentCycle(for: item, context: context) ?? {
            let created = WatchCycle(mediaID: item.id, kind: cycleKind(for: item), startedAt: now)
            context.insert(created)
            return created
        }()

        snapshotCurrentProgress(item: item, into: cycle, context: context, now: now, source: source)
        cycle.completedAt = now
        cycle.isComplete = true
        cycle.state = .completed
    }

    static func recordEpisodeMutation(
        mediaID: String,
        episodeID: String,
        watchedAt: Date,
        runtimeMinutes: Int?,
        isWatched: Bool,
        context: ModelContext,
        source: WatchEventSource = .automatic
    ) {
        let cycle: WatchCycle
        if let current = currentCycle(forMediaID: mediaID, context: context), current.state == .active {
            cycle = current
        } else if isWatched {
            let created = WatchCycle(mediaID: mediaID, kind: .tvShow, startedAt: watchedAt)
            context.insert(created)
            cycle = created
        } else {
            return
        }

        let scope = Set(cycle.scopeEpisodeIDs)
        guard scope.isEmpty || scope.contains(episodeID) else { return }
        if isWatched && !cycle.isRewatch && !scope.contains(episodeID) {
            cycle.scopeEpisodeIDs.append(episodeID)
        }

        let cycleID = cycle.id
        let events = (try? context.fetch(
            FetchDescriptor<WatchEvent>(predicate: #Predicate { $0.cycleID == cycleID })
        )) ?? []
        let activeEvent = events.first { $0.episodeID == episodeID && $0.isActive }
        let deduplicationKey = "\(cycle.id.uuidString):\(episodeID):watch"

        if isWatched {
            guard activeEvent == nil else { return }
            context.insert(WatchEvent(
                cycleID: cycle.id,
                mediaID: mediaID,
                episodeID: episodeID,
                watchedAt: watchedAt,
                source: source,
                runtimeMinutes: runtimeMinutes,
                deduplicationKey: deduplicationKey
            ))
        } else {
            activeEvent?.voidedAt = Date()
        }
    }

    nonisolated static func recordImportedMovie(
        mediaID: String,
        watchedAt: Date,
        runtimeMinutes: Int?,
        context: ModelContext
    ) {
        let activeRaw = WatchCycleState.active.rawValue
        let activeDescriptor = FetchDescriptor<WatchCycle>(
            predicate: #Predicate { cycle in
                cycle.mediaID == mediaID && cycle.stateRaw == activeRaw
            },
            sortBy: [SortDescriptor(\WatchCycle.startedAt, order: .reverse)]
        )
        let cycle: WatchCycle
        if let existing = try? context.fetch(activeDescriptor).first {
            cycle = existing
        } else {
            let created = WatchCycle(
                mediaID: mediaID,
                kind: .movie,
                startedAt: watchedAt
            )
            context.insert(created)
            cycle = created
        }
        let cycleID = cycle.id
        let events = (try? context.fetch(
            FetchDescriptor<WatchEvent>(predicate: #Predicate { $0.cycleID == cycleID })
        )) ?? []
        if let event = events.first(where: { $0.episodeID == nil && $0.isActive }) {
            event.watchedAt = watchedAt
            event.runtimeMinutes = runtimeMinutes
        } else {
            context.insert(WatchEvent(
                cycleID: cycle.id,
                mediaID: mediaID,
                watchedAt: watchedAt,
                source: .imported,
                runtimeMinutes: runtimeMinutes,
                deduplicationKey: "\(cycle.id.uuidString):movie:import"
            ))
        }
    }

    nonisolated static func updateEpisodeWatchDate(
        mediaID: String,
        episodeID: String,
        watchedAt: Date,
        runtimeMinutes: Int?,
        context: ModelContext
    ) {
        let events = (try? context.fetch(
            FetchDescriptor<WatchEvent>(predicate: #Predicate { event in
                event.mediaID == mediaID && event.episodeID == episodeID && event.voidedAt == nil
            })
        )) ?? []
        if events.isEmpty {
            recordEpisodeMutation(
                mediaID: mediaID,
                episodeID: episodeID,
                watchedAt: watchedAt,
                runtimeMinutes: runtimeMinutes,
                isWatched: true,
                context: context
            )
            return
        }
        for event in events {
            event.watchedAt = watchedAt
        }
    }

    nonisolated static func recordImportedEpisode(
        mediaID: String,
        episodeID: String,
        watchedAt: Date,
        runtimeMinutes: Int?,
        context: ModelContext
    ) {
        let activeRaw = WatchCycleState.active.rawValue
        let activeDescriptor = FetchDescriptor<WatchCycle>(
            predicate: #Predicate { cycle in
                cycle.mediaID == mediaID && cycle.stateRaw == activeRaw
            },
            sortBy: [SortDescriptor(\WatchCycle.startedAt, order: .reverse)]
        )
        let cycle: WatchCycle
        if let existing = try? context.fetch(activeDescriptor).first {
            cycle = existing
        } else {
            let created = WatchCycle(
                mediaID: mediaID,
                kind: .tvShow,
                startedAt: watchedAt
            )
            context.insert(created)
            cycle = created
        }

        let scope = Set(cycle.scopeEpisodeIDs)
        guard scope.isEmpty || scope.contains(episodeID) else { return }

        let cycleID = cycle.id
        let events = (try? context.fetch(
            FetchDescriptor<WatchEvent>(predicate: #Predicate { $0.cycleID == cycleID })
        )) ?? []
        guard !events.contains(where: { $0.episodeID == episodeID && $0.isActive }) else { return }
        context.insert(WatchEvent(
            cycleID: cycle.id,
            mediaID: mediaID,
            episodeID: episodeID,
            watchedAt: watchedAt,
            source: .imported,
            runtimeMinutes: runtimeMinutes,
            deduplicationKey: "\(cycle.id.uuidString):\(episodeID):import"
        ))
    }

    nonisolated static func deleteHistory(for mediaID: String, context: ModelContext) {
        let events = (try? context.fetch(
            FetchDescriptor<WatchEvent>(predicate: #Predicate { $0.mediaID == mediaID })
        )) ?? []
        let cycles = (try? context.fetch(
            FetchDescriptor<WatchCycle>(predicate: #Predicate { $0.mediaID == mediaID })
        )) ?? []
        for event in events { context.delete(event) }
        for cycle in cycles { context.delete(cycle) }
    }

    nonisolated static func remapHistory(from oldMediaID: String, to newMediaID: String, context: ModelContext) {
        let events = (try? context.fetch(
            FetchDescriptor<WatchEvent>(predicate: #Predicate { $0.mediaID == oldMediaID })
        )) ?? []
        let cycles = (try? context.fetch(
            FetchDescriptor<WatchCycle>(predicate: #Predicate { $0.mediaID == oldMediaID })
        )) ?? []
        for event in events { event.mediaID = newMediaID }
        for cycle in cycles { cycle.mediaID = newMediaID }
    }

    private static func cycleKind(for item: MediaItem) -> WatchCycleKind {
        item.type == .tvShow ? .tvShow : .movie
    }

    private static func currentCycle(for item: MediaItem, context: ModelContext) -> WatchCycle? {
        currentCycle(forMediaID: item.id, context: context)
    }

    private static func currentCycle(forMediaID mediaID: String, context: ModelContext) -> WatchCycle? {
        let active = WatchCycleState.active.rawValue
        let completed = WatchCycleState.completed.rawValue
        var descriptor = FetchDescriptor<WatchCycle>(
            predicate: #Predicate { cycle in
                cycle.mediaID == mediaID && (cycle.stateRaw == active || cycle.stateRaw == completed)
            },
            sortBy: [SortDescriptor(\WatchCycle.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private static func knownEpisodeIDs(for item: MediaItem) -> [String] {
        guard item.type == .tvShow, let details = item.tvShowDetails else { return [] }
        return details.seasons.liveModels.flatMap { season in
            season.episodes.liveModels.map {
                $0.uniqueID ?? "\(item.id)_\(season.seasonNumber)_\($0.episodeNumber)"
            }
        }
    }

    static func reconcileEpisodeCatalog(
        item: MediaItem,
        mediaID: String,
        knownIDs: [String],
        context: ModelContext,
        now: Date = Date()
    ) {
        guard item.modelContext != nil,
              !item.isDeleted,
              let cycle = currentCycle(forMediaID: mediaID, context: context),
              cycle.state == .active else { return }

        let known = Set(knownIDs)
        let scoped = Set(cycle.scopeEpisodeIDs)
        guard cycle.isRewatch, !scoped.isEmpty else {
            if !cycle.isRewatch {
                cycle.scopeEpisodeIDs = Array(known.union(scoped))
            }
            return
        }

        let newIDs = known.subtracting(scoped)
        guard !newIDs.isEmpty else { return }

        cycle.state = .paused
        let cycleID = cycle.id
        let events = (try? context.fetch(
            FetchDescriptor<WatchEvent>(predicate: #Predicate { $0.cycleID == cycleID })
        )) ?? []
        let datesByEpisode: [String: Date] = events.reduce(into: [:]) { result, event in
            guard let episodeID = event.episodeID, event.isActive else { return }
            result[episodeID] = event.watchedAt
        }

        if let details = item.tvShowDetails {
            for season in details.seasons.liveModels {
                for episode in season.episodes.liveModels {
                    let episodeID = episode.uniqueID ?? "\(mediaID)_\(season.seasonNumber)_\(episode.episodeNumber)"
                    guard scoped.contains(episodeID) else { continue }
                    episode.restoreWatchedProjection(from: datesByEpisode[episodeID])
                }
            }
            details.recalculateCachedProperties(triggerSync: false)
        }

        let next = WatchCycle(
            mediaID: mediaID,
            kind: .tvShow,
            startedAt: now,
            scopeEpisodeIDs: Array(newIDs)
        )
        context.insert(next)
        if item.state == .rewatching {
            item.stateValue = MediaState.active.rawValue
            item.lastInteractionDate = now
            item.lastStateChangeDate = now
        }
    }

    private static func snapshotCurrentProgress(
        item: MediaItem,
        into cycle: WatchCycle,
        context: ModelContext,
        now: Date,
        source: WatchEventSource
    ) {
        let cycleID = cycle.id
        let existing = (try? context.fetch(
            FetchDescriptor<WatchEvent>(predicate: #Predicate { $0.cycleID == cycleID })
        )) ?? []
        var keys = Set(existing.map(\.deduplicationKey))

        if item.type == .movie {
            if existing.contains(where: { $0.episodeID == nil && $0.isActive }) { return }
            let key = "\(cycle.id.uuidString):movie"
            guard keys.insert(key).inserted else { return }
            context.insert(WatchEvent(
                cycleID: cycle.id,
                mediaID: item.id,
                watchedAt: item.lastStateChangeDate ?? item.lastInteractionDate ?? now,
                source: source,
                runtimeMinutes: item.cachedRuntime,
                deduplicationKey: key,
                isBackfilled: cycle.isBackfilled
            ))
            return
        }

        guard let details = item.tvShowDetails else { return }
        let scope = Set(cycle.scopeEpisodeIDs)
        for season in details.seasons.liveModels {
            for episode in season.episodes.liveModels where episode.isWatched {
                let episodeID = episode.uniqueID ?? "\(item.id)_\(season.seasonNumber)_\(episode.episodeNumber)"
                guard scope.isEmpty || scope.contains(episodeID) else { continue }
                let key = "\(cycle.id.uuidString):\(episodeID)"
                guard keys.insert(key).inserted else { continue }
                context.insert(WatchEvent(
                    cycleID: cycle.id,
                    mediaID: item.id,
                    episodeID: episodeID,
                    watchedAt: episode.watchedDate ?? episode.lastWatchedDate ?? now,
                    source: source,
                    runtimeMinutes: episode.runtime,
                    deduplicationKey: key,
                    isBackfilled: cycle.isBackfilled
                ))
            }
        }
    }

    private static func resetCurrentProjection(item: MediaItem) {
        if item.type == .movie {
            item.storedProgress = 0
            item.storedWatchProgressLabel = nil
            return
        }

        guard let details = item.tvShowDetails else { return }
        for season in details.seasons.liveModels {
            for episode in season.episodes.liveModels {
                // Clears only the current projection (isWatched + watchedDate /
                // lastWatchedDate). `firstWatchedDate` is deliberately untouched —
                // the original first watch survives into the new cycle.
                episode.markWatched(false, recordHistory: false)
            }
        }
        details.recalculateCachedProperties(triggerSync: false)
        item.syncCachedProperties(dirty: [.progress, .badge])
    }
}
