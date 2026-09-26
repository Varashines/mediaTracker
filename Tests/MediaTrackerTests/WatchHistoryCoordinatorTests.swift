import XCTest
import SwiftData
@testable import MediaTracker

@MainActor
final class WatchHistoryCoordinatorTests: MTTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
            WatchCycle.self, WatchEvent.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testAddingTVTitleCatalogCheckDoesNotReadInvalidModel() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let previousContainer = DataService.modelContainer
        DataService.modelContainer = container
        defer { DataService.modelContainer = previousContainer }

        let item = MediaItem(id: "tv_add", title: "New Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 9001)
        details.item = item
        item.tvShowDetails = details

        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 9001)
        season.tvShowDetails = details
        details.seasons.append(season)

        let episode = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Episode 1", overview: "", showID: 9001)
        episode.season = season
        season.episodes.append(episode)

        context.insert(item)
        context.insert(details)
        context.insert(season)
        context.insert(episode)
        try context.save()

        item.syncTVProperties(now: Date(), currentState: .wishlist, skipNetwork: true, forceRecalculate: true)
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(item.isDeleted)
    }

    func testAutomaticStateCompletionUpdatesHistoryBeforeSave() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "movie_auto", title: "Movie", overview: "", type: .movie)
        item.stateValue = MediaState.active.rawValue
        context.insert(item)

        item.applyAutomaticState(.completed, now: Date(timeIntervalSince1970: 200))
        try context.save()

        let cycles = try context.fetch(FetchDescriptor<WatchCycle>())
        XCTAssertEqual(cycles.count, 1)
        XCTAssertEqual(cycles[0].state, .completed)
        XCTAssertTrue(cycles[0].isComplete)
    }

    func testMovieRewatchArchivesPreviousCycleAndStartsFresh() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "movie_1", title: "Movie", overview: "", type: .movie)
        item.stateValue = MediaState.completed.rawValue
        item.lastStateChangeDate = Date(timeIntervalSince1970: 100)
        context.insert(item)

        let now = Date(timeIntervalSince1970: 200)
        let active = WatchHistoryCoordinator.startRewatch(item: item, context: context, now: now)
        try context.save()

        let cycles = try context.fetch(FetchDescriptor<WatchCycle>())
        let archivedRaw = WatchCycleState.archived.rawValue
        let archived = try context.fetch(FetchDescriptor<WatchCycle>(predicate: #Predicate {
            $0.stateRaw == archivedRaw
        }))
        XCTAssertEqual(cycles.count, 2)
        XCTAssertEqual(active.state, .active)
        XCTAssertEqual(archived.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchEvent>()).count, 1)
        XCTAssertEqual(item.storedProgress, 0)
    }

    func testInterruptedRewatchIsArchivedAsIncomplete() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "movie_partial", title: "Movie", overview: "", type: .movie)
        item.stateValue = MediaState.completed.rawValue
        context.insert(item)

        _ = WatchHistoryCoordinator.startRewatch(item: item, context: context, now: Date(timeIntervalSince1970: 100))
        _ = WatchHistoryCoordinator.startRewatch(item: item, context: context, now: Date(timeIntervalSince1970: 200))
        try context.save()

        let archivedRaw = WatchCycleState.archived.rawValue
        let archived = try context.fetch(FetchDescriptor<WatchCycle>(predicate: #Predicate {
            $0.stateRaw == archivedRaw && $0.isRewatch
        }))
        XCTAssertEqual(archived.count, 1)
        XCTAssertFalse(archived[0].isComplete)
    }

    func testCompletingMovieRewatchCreatesSecondCompletionEvent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "movie_2", title: "Movie", overview: "", type: .movie)
        item.stateValue = MediaState.completed.rawValue
        context.insert(item)
        _ = WatchHistoryCoordinator.startRewatch(item: item, context: context, now: Date(timeIntervalSince1970: 100))

        WatchHistoryCoordinator.completeCurrentCycle(
            item: item,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        let activeRaw = WatchCycleState.active.rawValue
        let active = try context.fetch(FetchDescriptor<WatchCycle>(predicate: #Predicate {
            $0.stateRaw == activeRaw
        }))
        XCTAssertEqual(active.count, 0)
        let events = try context.fetch(FetchDescriptor<WatchEvent>())
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.map(\.cycleID)).count, 2)
    }

    func testHistoryRepairRemovesOrphanedRows() async throws {
        let versionKey = UserDefaultsKeys.watchHistoryRepairV1.rawValue
        UserDefaults.standard.set(0, forKey: versionKey)
        defer { UserDefaults.standard.removeObject(forKey: versionKey) }

        let container = try makeContainer()
        let context = container.mainContext
        let cycle = WatchCycle(mediaID: "deleted_media", kind: .movie)
        context.insert(cycle)
        context.insert(WatchEvent(
            cycleID: cycle.id,
            mediaID: cycle.mediaID,
            watchedAt: Date(),
            deduplicationKey: "orphan"
        ))
        try context.save()

        await DatabaseMigrations.runWatchHistoryRepairIfNeeded(container: container)

        XCTAssertTrue(try context.fetch(FetchDescriptor<WatchCycle>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<WatchEvent>()).isEmpty)
    }

    func testLegacyBackfillCreatesHistoryAndIsIdempotent() async throws {
        let versionKey = UserDefaultsKeys.watchHistoryBackfillV1.rawValue
        UserDefaults.standard.set(0, forKey: versionKey)
        defer { UserDefaults.standard.removeObject(forKey: versionKey) }

        let container = try makeContainer()
        let context = container.mainContext
        let movie = MediaItem(id: "movie_legacy", title: "Legacy Movie", overview: "", type: .movie)
        movie.stateValue = MediaState.completed.rawValue
        movie.lastStateChangeDate = Date(timeIntervalSince1970: 100)
        context.insert(movie)

        let show = MediaItem(id: "tv_99", title: "Legacy Show", overview: "", type: .tvShow)
        show.stateValue = MediaState.completed.rawValue
        let details = TVShowDetails(tmdbID: 99)
        details.item = show
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 99)
        season.tvShowDetails = details
        let episode = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Episode 1", overview: "", showID: 99)
        episode.season = season
        episode.markWatched(true)
        episode.watchedDate = Date(timeIntervalSince1970: 100)
        context.insert(show)
        context.insert(details)
        context.insert(season)
        context.insert(episode)
        try context.save()

        await DatabaseMigrations.runWatchHistoryBackfillIfNeeded(container: container)
        let firstCycleCount = try context.fetch(FetchDescriptor<WatchCycle>()).count
        let firstEventCount = try context.fetch(FetchDescriptor<WatchEvent>()).count
        XCTAssertEqual(firstCycleCount, 2)
        XCTAssertEqual(firstEventCount, 2)

        await DatabaseMigrations.runWatchHistoryBackfillIfNeeded(container: container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchCycle>()).count, firstCycleCount)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchEvent>()).count, firstEventCount)
    }

    func testImportedEpisodeRestoresBackedUpDateWithoutDuplicates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let watchedAt = Date(timeIntervalSince1970: 12345)

        WatchHistoryCoordinator.recordImportedEpisode(
            mediaID: "tv_7",
            episodeID: "tv_7_1_1",
            watchedAt: watchedAt,
            runtimeMinutes: 42,
            context: context
        )
        WatchHistoryCoordinator.recordImportedEpisode(
            mediaID: "tv_7",
            episodeID: "tv_7_1_1",
            watchedAt: watchedAt,
            runtimeMinutes: 42,
            context: context
        )
        try context.save()

        let events = try context.fetch(FetchDescriptor<WatchEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].source, .imported)
        XCTAssertEqual(events[0].watchedAt, watchedAt)
    }

    func testImportedMovieRestoresBackedUpDateWithoutDuplicates() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let watchedAt = Date(timeIntervalSince1970: 12345)

        WatchHistoryCoordinator.recordImportedMovie(
            mediaID: "movie_import",
            watchedAt: watchedAt,
            runtimeMinutes: 100,
            context: context
        )
        WatchHistoryCoordinator.recordImportedMovie(
            mediaID: "movie_import",
            watchedAt: watchedAt,
            runtimeMinutes: 100,
            context: context
        )
        try context.save()

        let events = try context.fetch(FetchDescriptor<WatchEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].source, .imported)
        XCTAssertEqual(events[0].watchedAt, watchedAt)
    }

    func testUpdatingEpisodeDateUpdatesActiveHistoryEvent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalDate = Date(timeIntervalSince1970: 100)
        let editedDate = Date(timeIntervalSince1970: 200)

        WatchHistoryCoordinator.recordEpisodeMutation(
            mediaID: "tv_8",
            episodeID: "tv_8_1_1",
            watchedAt: originalDate,
            runtimeMinutes: 42,
            isWatched: true,
            context: context
        )
        WatchHistoryCoordinator.updateEpisodeWatchDate(
            mediaID: "tv_8",
            episodeID: "tv_8_1_1",
            watchedAt: editedDate,
            runtimeMinutes: 42,
            context: context
        )
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchEvent>()).first?.watchedAt, editedDate)
    }

    func testEpisodeMutationRecordsAndVoidsOnlyActiveCycleEvent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let watchedAt = Date(timeIntervalSince1970: 100)
        let episodeID = "tv_1_1_1"

        WatchHistoryCoordinator.recordEpisodeMutation(
            mediaID: "tv_1",
            episodeID: episodeID,
            watchedAt: watchedAt,
            runtimeMinutes: 42,
            isWatched: true,
            context: context
        )
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchEvent>()).count, 1)

        WatchHistoryCoordinator.recordEpisodeMutation(
            mediaID: "tv_1",
            episodeID: episodeID,
            watchedAt: watchedAt,
            runtimeMinutes: 42,
            isWatched: false,
            context: context
        )
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchEvent>()).filter(\.isActive).count, 0)

        WatchHistoryCoordinator.recordEpisodeMutation(
            mediaID: "tv_1",
            episodeID: episodeID,
            watchedAt: watchedAt,
            runtimeMinutes: 42,
            isWatched: true,
            context: context
        )
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchEvent>()).filter(\.isActive).count, 1)
    }

    func testNewSeasonPausesRewatchAndStartsNewFirstWatchCycle() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "tv_1", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 1)
        details.item = item
        let seasonOne = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 1)
        seasonOne.tvShowDetails = details
        let episodeOne = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Episode 1", overview: "", showID: 1)
        episodeOne.season = seasonOne
        episodeOne.markWatched(true)
        episodeOne.watchedDate = Date(timeIntervalSince1970: 100)
        context.insert(item)
        context.insert(details)
        context.insert(seasonOne)
        context.insert(episodeOne)

        _ = WatchHistoryCoordinator.startRewatch(
            item: item,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )

        let seasonTwo = TVSeason(seasonNumber: 2, name: "Season 2", episodeCount: 1, showID: 1)
        seasonTwo.tvShowDetails = details
        let episodeTwo = TVEpisode(episodeNumber: 1, seasonNumber: 2, name: "Episode 1", overview: "", showID: 1)
        episodeTwo.season = seasonTwo
        context.insert(seasonTwo)
        context.insert(episodeTwo)
        item.stateValue = MediaState.rewatching.rawValue

        let oldID = episodeOne.uniqueID!
        let newID = episodeTwo.uniqueID!
        WatchHistoryCoordinator.reconcileEpisodeCatalog(
            item: item,
            mediaID: item.id,
            knownIDs: [oldID, newID],
            context: context,
            now: Date(timeIntervalSince1970: 300)
        )
        try context.save()

        let cycles = try context.fetch(FetchDescriptor<WatchCycle>())
        let paused = cycles.first { $0.state == .paused }
        let active = cycles.first { $0.state == .active }
        XCTAssertEqual(paused?.scopeEpisodeIDs, [oldID])
        XCTAssertEqual(active?.scopeEpisodeIDs, [newID])
        XCTAssertFalse(active?.isRewatch ?? true)
        XCTAssertTrue(episodeOne.isWatched)
        XCTAssertFalse(episodeTwo.isWatched)
        XCTAssertEqual(item.state, .active)

        // Completing the title also finalizes the paused rewatch: it never
        // reached full coverage (the rewatch recorded no events), so it is
        // archived as a partial attempt and no longer resumable.
        WatchHistoryCoordinator.completeCurrentCycle(
            item: item,
            context: context,
            now: Date(timeIntervalSince1970: 400)
        )
        try context.save()

        let cyclesAfterCompletion = try context.fetch(FetchDescriptor<WatchCycle>())
        let finalized = try XCTUnwrap(cyclesAfterCompletion.first { $0.id == paused?.id })
        XCTAssertEqual(finalized.state, .archived)
        XCTAssertFalse(finalized.isComplete)
        XCTAssertNil(
            WatchHistoryCoordinator.resumePausedRewatch(
                item: item,
                context: context,
                now: Date(timeIntervalSince1970: 500)
            ),
            "a completed title must not offer Resume Paused Rewatch"
        )
    }

    /// Closing a rewatch cycle must not append a second event for episodes that
    /// were already logged while watching: the two writers use different
    /// deduplication keys ("<cycle>:<episode>:watch" vs "<cycle>:<episode>"), so
    /// key matching alone duplicated every episode.
    func testCompletingRewatchCycleDoesNotDuplicateEpisodeEvents() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "tv_4", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 4)
        details.item = item
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 4)
        season.tvShowDetails = details
        let episode = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Episode 1", overview: "", showID: 4)
        episode.season = season
        season.episodes.append(episode)
        details.seasons.append(season)
        item.stateValue = MediaState.completed.rawValue
        context.insert(item)
        context.insert(details)
        context.insert(season)
        context.insert(episode)
        try context.save()

        let rewatch = WatchHistoryCoordinator.startRewatch(item: item, context: context)
        let episodeID = try XCTUnwrap(episode.uniqueID)

        // Watched during the rewatch — recorded with the ":watch" key.
        WatchHistoryCoordinator.recordEpisodeMutation(
            mediaID: item.id,
            episodeID: episodeID,
            watchedAt: Date(timeIntervalSince1970: 250),
            runtimeMinutes: 45,
            isWatched: true,
            context: context,
            source: .automatic
        )
        episode.markWatched(true, recordHistory: false)
        try context.save()

        // Finishing the rewatch closes the cycle and snapshots progress.
        item.state = .rewatching
        try context.save()
        episode.markWatched(true, recordHistory: false)
        item.syncCachedProperties(now: Date())
        try context.save()

        let rewatchEvents = try context.fetch(FetchDescriptor<WatchEvent>())
            .filter { $0.cycleID == rewatch.id && $0.isActive }
        XCTAssertEqual(
            rewatchEvents.count, 1,
            "one active event per (cycle, episode) — got keys: \(rewatchEvents.map(\.deduplicationKey))"
        )
    }

    /// Same flow, but the rewatch had finished its whole scope before the new
    /// season landed — the paused cycle must be recorded as a completed rewatch.
    func testFinalizingPausedRewatchMarksFullCoverageComplete() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "tv_3", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 3)
        details.item = item
        let seasonOne = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 3)
        seasonOne.tvShowDetails = details
        let episodeOne = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Episode 1", overview: "", showID: 3)
        episodeOne.season = seasonOne
        episodeOne.markWatched(true)
        context.insert(item)
        context.insert(details)
        context.insert(seasonOne)
        context.insert(episodeOne)
        try context.save()

        let rewatch = WatchHistoryCoordinator.startRewatch(item: item, context: context)
        let oldID = try XCTUnwrap(episodeOne.uniqueID)

        // Every episode in the rewatch scope was watched again.
        context.insert(WatchEvent(
            cycleID: rewatch.id,
            mediaID: item.id,
            episodeID: oldID,
            watchedAt: Date(timeIntervalSince1970: 250),
            deduplicationKey: "\(rewatch.id.uuidString):\(oldID)"
        ))

        // A new season arrives mid-rewatch.
        let seasonTwo = TVSeason(seasonNumber: 2, name: "Season 2", episodeCount: 1, showID: 3)
        seasonTwo.tvShowDetails = details
        let episodeTwo = TVEpisode(episodeNumber: 1, seasonNumber: 2, name: "Episode 1", overview: "", showID: 3)
        episodeTwo.season = seasonTwo
        context.insert(seasonTwo)
        context.insert(episodeTwo)
        item.stateValue = MediaState.rewatching.rawValue
        let newID = try XCTUnwrap(episodeTwo.uniqueID)

        WatchHistoryCoordinator.reconcileEpisodeCatalog(
            item: item,
            mediaID: item.id,
            knownIDs: [oldID, newID],
            context: context,
            now: Date(timeIntervalSince1970: 300)
        )
        try context.save()
        XCTAssertEqual(rewatch.state, .paused)

        // The title completes via the new season.
        WatchHistoryCoordinator.completeCurrentCycle(
            item: item,
            context: context,
            now: Date(timeIntervalSince1970: 400)
        )
        try context.save()

        XCTAssertEqual(rewatch.state, .completed)
        XCTAssertTrue(rewatch.isComplete, "a rewatch that covered its full scope counts as completed")
        XCTAssertNotNil(rewatch.completedAt)
    }

    func testTVRewatchArchivesEpisodesAndResetsCurrentProjection() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "tv_1", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 1)
        details.item = item
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 1)
        season.tvShowDetails = details
        let episode = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Episode 1", overview: "", showID: 1)
        episode.season = season
        episode.markWatched(true)
        episode.watchedDate = Date(timeIntervalSince1970: 100)
        item.stateValue = MediaState.completed.rawValue
        context.insert(item)
        context.insert(details)
        context.insert(season)
        context.insert(episode)

        let active = WatchHistoryCoordinator.startRewatch(
            item: item,
            context: context,
            now: Date(timeIntervalSince1970: 200)
        )
        try context.save()

        XCTAssertEqual(active.state, .active)
        XCTAssertFalse(episode.isWatched)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchEvent>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchCycle>()).count, 2)
    }

    /// Finishing a rewatch auto-completes the title and closes the cycle; the next
    /// Re-watching selection must then open a brand new cycle.
    func testFinishingRewatchCompletesTitleAndNextRewatchStartsFreshCycle() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let previousContainer = DataService.modelContainer
        DataService.modelContainer = container
        defer { DataService.modelContainer = previousContainer }

        let item = MediaItem(id: "tv_2", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 2)
        details.item = item
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 2)
        season.tvShowDetails = details
        let episode = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Episode 1", overview: "", showID: 2)
        episode.season = season
        season.episodes.append(episode)
        details.seasons.append(season)
        item.stateValue = MediaState.completed.rawValue
        context.insert(item)
        context.insert(details)
        context.insert(season)
        context.insert(episode)
        try context.save()

        // First rewatch: the projection resets.
        item.state = .rewatching
        try context.save()
        XCTAssertEqual(item.state, .rewatching)
        XCTAssertEqual(item.rewatchCount, 1)
        XCTAssertFalse(episode.isWatched)

        // Watch the only episode — progress hits 100% and the title completes.
        episode.markWatched(true, recordHistory: false)
        try context.save()
        item.syncCachedProperties(now: Date())
        try context.save()

        XCTAssertEqual(item.state, .completed, "finishing a rewatch completes the title")
        let cyclesAfterFinish = try context.fetch(FetchDescriptor<WatchCycle>())
        let finished = try XCTUnwrap(cyclesAfterFinish.first { $0.isRewatch })
        XCTAssertTrue(finished.isComplete, "the rewatch cycle is closed")
        XCTAssertEqual(finished.state, .completed)

        // Next rewatch must start a fresh cycle rather than resuming the old one.
        let previousCycleCount = cyclesAfterFinish.count
        item.state = .rewatching
        try context.save()

        let cycles = try context.fetch(FetchDescriptor<WatchCycle>())
        XCTAssertEqual(cycles.count, previousCycleCount + 1)
        XCTAssertEqual(item.rewatchCount, 2)
        let activeCycle = try XCTUnwrap(WatchHistoryCoordinator.currentCycle(for: item, context: context))
        XCTAssertTrue(activeCycle.isRewatch)
        XCTAssertFalse(activeCycle.isComplete)
        XCTAssertEqual(activeCycle.stateRaw, WatchCycleState.active.rawValue)
        XCTAssertFalse(episode.isWatched, "the projection resets again for the new cycle")
    }

    // MARK: - Multi-cycle routing

    /// Builds a show with two single-episode seasons and returns the pieces a
    /// rewatch test needs: the item, and the S1E1 / S2E1 episodes.
    private func makeTwoSeasonShow(
        in context: ModelContext,
        id: String,
        tmdbID: Int
    ) throws -> (MediaItem, TVEpisode, TVEpisode) {
        let item = MediaItem(id: id, title: "Show \(id)", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: tmdbID)
        details.item = item
        item.tvShowDetails = details
        var episodes: [TVEpisode] = []
        for seasonNumber in 1...2 {
            let season = TVSeason(seasonNumber: seasonNumber, name: "S\(seasonNumber)", episodeCount: 1, showID: tmdbID)
            season.tvShowDetails = details
            details.seasons.append(season)
            let episode = TVEpisode(
                episodeNumber: 1,
                seasonNumber: seasonNumber,
                name: "S\(seasonNumber)E1",
                overview: "",
                showID: tmdbID
            )
            episode.season = season
            season.episodes.append(episode)
            episodes.append(episode)
        }
        context.insert(item)
        context.insert(details)
        for season in details.seasons { context.insert(season) }
        episodes.forEach(context.insert)
        return (item, episodes[0], episodes[1])
    }

    /// A new season arriving while the rewatch is already paused must still get a
    /// cycle, otherwise its watch events are dropped even though the episodes
    /// count toward progress.
    func testNewSeasonArrivingWhileRewatchIsPausedStillOpensACycle() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "tv_10", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 10)
        details.item = item
        item.tvShowDetails = details
        let seasonOne = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 1, showID: 10)
        seasonOne.tvShowDetails = details
        details.seasons.append(seasonOne)
        let s1e1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "S1E1", overview: "", showID: 10)
        s1e1.season = seasonOne
        seasonOne.episodes.append(s1e1)
        s1e1.markWatched(true)
        item.stateValue = MediaState.completed.rawValue
        context.insert(item)
        context.insert(details)
        context.insert(seasonOne)
        context.insert(s1e1)
        try context.save()

        let s1ID = try XCTUnwrap(s1e1.uniqueID)
        _ = WatchHistoryCoordinator.startRewatch(item: item, context: context)
        item.stateValue = MediaState.rewatching.rawValue

        // Season 2 arrives and pauses the rewatch.
        let seasonTwo = TVSeason(seasonNumber: 2, name: "S2", episodeCount: 1, showID: 10)
        seasonTwo.tvShowDetails = details
        details.seasons.append(seasonTwo)
        let s2e1 = TVEpisode(episodeNumber: 1, seasonNumber: 2, name: "S2E1", overview: "", showID: 10)
        s2e1.season = seasonTwo
        seasonTwo.episodes.append(s2e1)
        context.insert(seasonTwo)
        context.insert(s2e1)
        try context.save()
        let s2ID = try XCTUnwrap(s2e1.uniqueID)

        WatchHistoryCoordinator.reconcileEpisodeCatalog(
            item: item,
            mediaID: item.id,
            knownIDs: [s1ID, s2ID],
            context: context
        )
        try context.save()

        let pausedRewatch = try XCTUnwrap(
            try context.fetch(FetchDescriptor<WatchCycle>()).first { $0.isRewatch && $0.state == .paused }
        )

        // More season 2 content shows up while the rewatch is still paused.
        let s2e2 = TVEpisode(episodeNumber: 2, seasonNumber: 2, name: "S2E2", overview: "", showID: 10)
        s2e2.season = seasonTwo
        seasonTwo.episodes.append(s2e2)
        context.insert(s2e2)
        let extraID = try XCTUnwrap(s2e2.uniqueID)
        try context.save()

        WatchHistoryCoordinator.reconcileEpisodeCatalog(
            item: item,
            mediaID: item.id,
            knownIDs: [s1ID, s2ID, extraID],
            context: context
        )
        try context.save()

        let cycles = try context.fetch(FetchDescriptor<WatchCycle>())
        XCTAssertEqual(pausedRewatch.state, .paused, "an already paused rewatch stays paused")
        XCTAssertTrue(
            cycles.contains { !$0.isRewatch && $0.scopeEpisodeIDs.contains(extraID) },
            "the new episode must belong to a cycle or its events are dropped"
        )
    }

    /// Resuming restarts the pass, so the previous attempt's events must be
    /// voided. Left active, the cycle looked fully covered even though its
    /// projection had just been cleared.
    func testResumingPausedRewatchVoidsThePreviousAttemptEvents() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "tv_11", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 11)
        details.item = item
        item.tvShowDetails = details
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 1, showID: 11)
        season.tvShowDetails = details
        details.seasons.append(season)
        let episode = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "E1", overview: "", showID: 11)
        episode.season = season
        season.episodes.append(episode)
        item.stateValue = MediaState.completed.rawValue
        context.insert(item)
        context.insert(details)
        context.insert(season)
        context.insert(episode)
        try context.save()

        let rewatch = WatchHistoryCoordinator.startRewatch(item: item, context: context)
        let episodeID = try XCTUnwrap(episode.uniqueID)
        context.insert(WatchEvent(
            cycleID: rewatch.id,
            mediaID: item.id,
            episodeID: episodeID,
            watchedAt: Date(timeIntervalSince1970: 250),
            deduplicationKey: "\(rewatch.id.uuidString):\(episodeID):watch"
        ))
        rewatch.state = .paused
        item.stateValue = MediaState.active.rawValue
        try context.save()

        let resumed = try XCTUnwrap(WatchHistoryCoordinator.resumePausedRewatch(item: item, context: context))
        try context.save()

        XCTAssertEqual(resumed.state, .active)
        XCTAssertTrue(
            ((try? context.fetch(FetchDescriptor<WatchEvent>())) ?? []).allSatisfy { $0.voidedAt != nil },
            "resuming restarts the pass, so the previous attempt's events must be voided"
        )
    }

    /// Completing a title must settle every other open cycle, otherwise a
    /// resumed rewatch stays `.active` forever: invisible in the stats, never
    /// returned by currentCycle, and still offering "Resume Paused Rewatch".
    func testCompletingTitleSettlesASecondOpenCycle() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "tv_12", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 12)
        details.item = item
        item.tvShowDetails = details
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 1, showID: 12)
        season.tvShowDetails = details
        details.seasons.append(season)
        let episode = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "E1", overview: "", showID: 12)
        episode.season = season
        season.episodes.append(episode)
        item.stateValue = MediaState.completed.rawValue
        context.insert(item)
        context.insert(details)
        context.insert(season)
        context.insert(episode)
        try context.save()

        // A stale older cycle alongside the current one, as left behind by the
        // old resume path: two open cycles for one title.
        let stale = WatchCycle(
            mediaID: item.id,
            kind: .tvShow,
            startedAt: Date(timeIntervalSince1970: 100),
            state: .active,
            isRewatch: true
        )
        let current = WatchCycle(
            mediaID: item.id,
            kind: .tvShow,
            startedAt: Date(timeIntervalSince1970: 200),
            state: .active
        )
        context.insert(stale)
        context.insert(current)
        try context.save()

        WatchHistoryCoordinator.completeCurrentCycle(item: item, context: context)
        try context.save()

        XCTAssertEqual(current.state, .completed, "the newest open cycle is the one that closes")
        XCTAssertEqual(
            stale.state, .archived,
            "a second open cycle must not stay active after the title completes"
        )
        XCTAssertFalse(stale.isComplete, "an uncovered rewatch is a partial attempt")
    }

    /// `Re-watching` has no downward auto-advance branch because a fresh rewatch
    /// also sits at 0%. An empty rewatch that reaches 0% was abandoned, so it
    /// should be settled and the pre-rewatch state restored.
    func testAbandonedEmptyRewatchIsSettledOnSync() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let previousContainer = DataService.modelContainer
        DataService.modelContainer = container
        defer { DataService.modelContainer = previousContainer }

        let item = MediaItem(id: "tv_13", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 13)
        details.item = item
        item.tvShowDetails = details
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 2, showID: 13)
        season.tvShowDetails = details
        details.seasons.append(season)
        var episodes: [TVEpisode] = []
        for i in 1...2 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "E\(i)", overview: "", showID: 13)
            ep.season = season
            season.episodes.append(ep)
            episodes.append(ep)
        }
        item.stateValue = MediaState.active.rawValue
        context.insert(item)
        context.insert(details)
        context.insert(season)
        episodes.forEach(context.insert)
        for ep in episodes { ep.markWatched(true) }
        try context.save()

        // Let the auto-advance complete the title, which is what creates the
        // completed first-watch cycle an abandoned rewatch is restored from.
        item.syncCachedProperties(now: Date())
        try context.save()
        XCTAssertEqual(item.state, .completed)
        try await Task.sleep(nanoseconds: 100_000_000)

        // Start a rewatch, watch an episode, then change your mind. A rewatch
        // that was merely started also sits at 0% with an empty cycle, so the
        // interaction is what distinguishes an abandoned pass from a fresh one.
        item.state = .rewatching
        try context.save()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(item.state, .rewatching, "a freshly started rewatch is left alone")

        episodes[0].markWatched(true)
        try context.save()
        try await Task.sleep(nanoseconds: 50_000_000)
        episodes[0].markWatched(false)
        try context.save()

        item.syncCachedProperties(now: Date())
        try context.save()

        XCTAssertEqual(
            item.state, .completed,
            "an abandoned rewatch restores the state the title held before it"
        )
        let cycles = try context.fetch(FetchDescriptor<WatchCycle>())
        XCTAssertTrue(
            cycles.contains { $0.isRewatch && $0.state == .archived },
            "the abandoned rewatch is archived, not left active"
        )
    }

    /// A rewatch that is genuinely in progress must not be settled just because
    /// progress is not yet 100%. Single season, so the catalog check cannot
    /// introduce a second cycle and pause the pass.
    func testRewatchInProgressIsNotSettledBySync() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let previousContainer = DataService.modelContainer
        DataService.modelContainer = container
        defer { DataService.modelContainer = previousContainer }

        let item = MediaItem(id: "tv_14", title: "Show", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 14)
        details.item = item
        item.tvShowDetails = details
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 2, showID: 14)
        season.tvShowDetails = details
        details.seasons.append(season)
        var episodes: [TVEpisode] = []
        for i in 1...2 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "E\(i)", overview: "", showID: 14)
            ep.season = season
            season.episodes.append(ep)
            episodes.append(ep)
        }
        item.stateValue = MediaState.completed.rawValue
        context.insert(item)
        context.insert(details)
        context.insert(season)
        episodes.forEach(context.insert)
        for ep in episodes { ep.markWatched(true) }
        try context.save()

        item.state = .rewatching
        episodes[0].markWatched(true, recordHistory: false)
        try context.save()
        try await Task.sleep(nanoseconds: 100_000_000)

        item.syncCachedProperties(now: Date())
        try context.save()

        XCTAssertEqual(item.state, .rewatching, "a rewatch with progress is left alone")
    }

    /// A first-watch cycle must adopt every episode it is handed. Previously a
    /// non-empty scope silently dropped out-of-scope episodes, so a bulk pass
    /// lost every event after the first.
    func testFirstWatchCycleAdoptsOutOfScopeEpisodes() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (item, s1e1, s2e1) = try makeTwoSeasonShow(in: context, id: "tv_15", tmdbID: 15)
        try context.save()
        let s1ID = try XCTUnwrap(s1e1.uniqueID)
        let s2ID = try XCTUnwrap(s2e1.uniqueID)

        // Two bulk-style mutations back to back, as a "mark all watched" pass does.
        for episodeID in [s1ID, s2ID] {
            WatchHistoryCoordinator.recordEpisodeMutation(
                mediaID: item.id,
                episodeID: episodeID,
                watchedAt: Date(),
                runtimeMinutes: 42,
                isWatched: true,
                context: context
            )
        }
        try context.save()

        let events = try context.fetch(FetchDescriptor<WatchEvent>())
            .filter { $0.isActive && $0.mediaID == item.id }
        XCTAssertEqual(
            Set(events.compactMap(\.episodeID)), [s1ID, s2ID],
            "a first-watch cycle must not drop episodes outside its current scope"
        )
    }
}
