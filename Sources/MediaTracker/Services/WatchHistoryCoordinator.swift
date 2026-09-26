import Foundation
import SwiftData

enum WatchHistoryCoordinator {
    static func handleStateChange(
        item: MediaItem,
        from oldState: MediaState?,
        to newState: MediaState,
        context: ModelContext,
        now: Date = Date(),
        legacyCompletedAt: Date? = nil,
        source: WatchEventSource = .manual
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
            completeCurrentCycle(item: item, context: context, now: now, source: source)
            return
        }

        if newState == .completed, oldState != .completed, oldState != .rewatching {
            completeCurrentCycle(item: item, context: context, now: now, source: source)
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
        // Resuming restarts the pass, so the previous attempt's events must be
        // voided. They stayed active before, which meant the cycle looked fully
        // covered even though the projection had just been cleared, and the
        // re-watch recorded nothing.
        voidActiveEvents(inCycle: paused, context: context, at: now)
        item.stateValue = MediaState.rewatching.rawValue
        item.lastInteractionDate = now
        item.lastStateChangeDate = now
        item.storedProgress = 0
        item.storedWatchProgressLabel = nil
        return paused
    }

    /// Voids every active event in a cycle, used when a pass is restarted.
    static func voidActiveEvents(inCycle cycle: WatchCycle, context: ModelContext, at date: Date) {
        let cycleID = cycle.id
        let descriptor = FetchDescriptor<WatchEvent>(
            predicate: #Predicate<WatchEvent> { event in
                event.cycleID == cycleID && event.voidedAt == nil
            }
        )
        for event in (try? context.fetch(descriptor)) ?? [] {
            event.voidedAt = date
        }
    }

    static func completeCurrentCycle(
        item: MediaItem,
        context: ModelContext,
        now: Date = Date(),
        source: WatchEventSource = .manual
    ) {
        // A title can hold more than one open cycle: a new season arriving
        // mid-rewatch pauses the scoped rewatch and opens a first-watch cycle for
        // the new episodes, and resuming can leave both `.active`. Closing only
        // the newest used to strand the other as `.active` forever — invisible in
        // the stats, still holding events, and never returned by `currentCycle`.
        let open = openCycles(forMediaID: item.id, context: context)
        let cycle: WatchCycle
        if let newest = open.first {
            cycle = newest
        } else {
            let created = WatchCycle(mediaID: item.id, kind: cycleKind(for: item), startedAt: now)
            context.insert(created)
            cycle = created
        }

        snapshotCurrentProgress(item: item, into: cycle, context: context, now: now, source: source)
        cycle.completedAt = now
        cycle.isComplete = true
        cycle.state = .completed
        settleSupersededCycles(item: item, context: context, now: now, keeping: cycle.id)
    }

    /// Settles every other open cycle once the title completes. A rewatch that
    /// covered its whole scope is recorded as a completed rewatch; anything else
    /// is archived as a partial attempt. Either way it stops lingering in
    /// `.active`/`.paused`, which is what kept "Resume Paused Rewatch" on offer
    /// for a completed title and left stale cycles in the stats.
    private static func settleSupersededCycles(
        item: MediaItem,
        context: ModelContext,
        now: Date,
        keeping keptCycleID: UUID
    ) {
        guard item.type == .tvShow else { return }
        let mediaID = item.id
        let activeRaw = WatchCycleState.active.rawValue
        let pausedRaw = WatchCycleState.paused.rawValue
        let descriptor = FetchDescriptor<WatchCycle>(
            predicate: #Predicate { cycle in
                cycle.mediaID == mediaID
                    && (cycle.stateRaw == activeRaw || cycle.stateRaw == pausedRaw)
            }
        )
        let superseded = ((try? context.fetch(descriptor)) ?? []).filter { $0.id != keptCycleID }
        guard !superseded.isEmpty else { return }

        for cycle in superseded {
            if cycle.isRewatch, coveredEveryEpisode(cycle, context: context) {
                cycle.isComplete = true
                cycle.state = .completed
                cycle.completedAt = cycle.completedAt ?? now
            } else {
                cycle.state = .archived
            }
        }
    }

    /// True when every episode the cycle was scoped to has an active event in it.
    private static func coveredEveryEpisode(_ cycle: WatchCycle, context: ModelContext) -> Bool {
        let cycleID = cycle.id
        var eventDescriptor = FetchDescriptor<WatchEvent>(
            predicate: #Predicate<WatchEvent> { event in
                event.cycleID == cycleID && event.voidedAt == nil
            }
        )
        eventDescriptor.propertiesToFetch = [\.episodeID]
        let watchedIDs = Set(((try? context.fetch(eventDescriptor)) ?? []).compactMap(\.episodeID))
        let scope = Set(cycle.scopeEpisodeIDs)
        // An unscoped cycle can't be judged by coverage, so require at least one
        // logged episode rather than treating it as a completed rewatch.
        return scope.isEmpty ? !watchedIDs.isEmpty : scope.subtracting(watchedIDs).isEmpty
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
        if let owning = openCycle(forMediaID: mediaID, episodeID: episodeID, context: context),
           owning.state == .active {
            cycle = owning
        } else if isWatched {
            let created = WatchCycle(mediaID: mediaID, kind: .tvShow, startedAt: watchedAt)
            context.insert(created)
            cycle = created
        } else {
            return
        }

        // A rewatch keeps the scope it was opened with, but a first-watch cycle
        // adopts any episode it is handed. Previously a non-empty first-watch
        // scope dropped every episode outside it, so bulk passes lost those
        // events until a catalog check happened to widen the scope.
        var scope = Set(cycle.scopeEpisodeIDs)
        if isWatched && !cycle.isRewatch && !scope.contains(episodeID) {
            cycle.scopeEpisodeIDs.append(episodeID)
            scope.insert(episodeID)
        }
        if cycle.isRewatch, !scope.isEmpty, !scope.contains(episodeID) { return }

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

    static func currentCycle(for item: MediaItem, context: ModelContext) -> WatchCycle? {
        currentCycle(forMediaID: item.id, context: context)
    }

    static func currentCycle(forMediaID mediaID: String, context: ModelContext) -> WatchCycle? {
        openCycles(forMediaID: mediaID, context: context).first
    }

    /// Every cycle that can still accept events, newest first.
    ///
    /// A title can legitimately have more than one open cycle: a new season
    /// arriving mid-rewatch pauses the scoped rewatch and opens a first-watch
    /// cycle for the new episodes. Resuming the rewatch then leaves two `.active`
    /// cycles, so "newest wins" is not a safe way to pick one.
    static func openCycles(forMediaID mediaID: String, context: ModelContext) -> [WatchCycle] {
        let active = WatchCycleState.active.rawValue
        let completed = WatchCycleState.completed.rawValue
        let descriptor = FetchDescriptor<WatchCycle>(
            predicate: #Predicate { cycle in
                cycle.mediaID == mediaID && (cycle.stateRaw == active || cycle.stateRaw == completed)
            },
            sortBy: [SortDescriptor(\WatchCycle.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The open cycle that owns `episodeID`. Prefers a cycle whose scope already
    /// lists the episode, then a rewatch, then the newest — so an episode is
    /// always logged to the pass that is actually tracking it.
    static func openCycle(
        forMediaID mediaID: String,
        episodeID: String,
        context: ModelContext
    ) -> WatchCycle? {
        let cycles = openCycles(forMediaID: mediaID, context: context)
        if let scoped = cycles.first(where: { $0.scopeEpisodeIDs.contains(episodeID) }) {
            return scoped
        }
        if let rewatch = cycles.first(where: \.isRewatch) {
            return rewatch
        }
        return cycles.first
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
        guard item.modelContext != nil, !item.isDeleted else { return }
        guard let cycle = openCycles(forMediaID: mediaID, context: context)
            .first(where: { $0.state == .active || ($0.state == .paused && $0.isRewatch) })
        else { return }

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

        // A rewatch that is already paused stays paused: the new episodes open
        // their own first-watch cycle and the paused pass is left for the user to
        // resume or settle. Previously the guard above required `.active`, so a
        // second season arriving while paused left those episodes in no cycle at
        // all — every watch event for them was dropped, even though they still
        // counted toward progress.
        let wasActive = cycle.state == .active
        if wasActive {
            cycle.state = .paused
        }
        let cycleID = cycle.id
        let events = (try? context.fetch(
            FetchDescriptor<WatchEvent>(predicate: #Predicate { $0.cycleID == cycleID })
        )) ?? []
        let datesByEpisode: [String: Date] = events.reduce(into: [:]) { result, event in
            guard let episodeID = event.episodeID, event.isActive else { return }
            result[episodeID] = event.watchedAt
        }

        if wasActive, let details = item.tvShowDetails {
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
        if wasActive, item.state == .rewatching {
            item.stateValue = MediaState.active.rawValue
            item.lastInteractionDate = now
            item.lastStateChangeDate = now
        }
    }

    /// A rewatch that was started and then left with nothing watched is not a
    /// rewatch — it is a title the user changed their mind about. `Re-watching`
    /// has no downward transition in the auto-advance rules (a fresh rewatch also
    /// sits at 0%), so the empty cycle is settled here instead: archived, and the
    /// title returns to the state it held before the rewatch.
    static func abandonEmptyRewatchIfNeeded(
        item: MediaItem,
        context: ModelContext,
        now: Date = Date()
    ) {
        guard item.state == .rewatching,
              (item.storedProgress ?? 0) <= 0,
              let cycle = openCycles(forMediaID: item.id, context: context)
                .first(where: { $0.isRewatch && $0.state == .active })
        else { return }

        // A rewatch that was started a moment ago also sits at 0% with an empty
        // cycle, so require evidence that episodes were touched during this pass:
        // `lastInteractionDate` moves whenever an episode is watched. Without
        // this, every fresh rewatch was cancelled by the sync its own state
        // change triggered.
        guard let lastInteraction = item.lastInteractionDate, lastInteraction > cycle.startedAt else { return }

        cycle.state = .archived
        cycle.completedAt = cycle.completedAt ?? now
        // Back to whatever the title was before the rewatch: completed if it had
        // a finished first-watch cycle, otherwise the wishlist. Archiving a cycle
        // moves it out of `.completed`, so judge it by `isComplete` the same way
        // the stats do.
        let mediaID = item.id
        let allCycles = (try? context.fetch(
            FetchDescriptor<WatchCycle>(predicate: #Predicate { $0.mediaID == mediaID })
        )) ?? []
        let completedRaw = WatchCycleState.completed.rawValue
        let hadCompletedFirstWatch = allCycles.contains { cycle in
            !cycle.isRewatch && (cycle.isComplete || cycle.stateRaw == completedRaw)
        }
        item.stateValue = (hadCompletedFirstWatch ? MediaState.completed : MediaState.wishlist).rawValue
        item.lastInteractionDate = now
        item.lastStateChangeDate = now
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
        // `recordEpisodeMutation` writes keys as "<cycle>:<episode>:watch" while
        // this snapshot writes "<cycle>:<episode>", so matching on the key alone
        // would add a second event for every episode already logged in this
        // cycle. Match on the episode instead, like the movie branch above.
        let alreadyLogged = Set(existing.filter(\.isActive).compactMap(\.episodeID))
        for season in details.seasons.liveModels {
            for episode in season.episodes.liveModels where episode.isWatched {
                let episodeID = episode.uniqueID ?? "\(item.id)_\(season.seasonNumber)_\(episode.episodeNumber)"
                guard scope.isEmpty || scope.contains(episodeID) else { continue }
                guard !alreadyLogged.contains(episodeID) else { continue }
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
