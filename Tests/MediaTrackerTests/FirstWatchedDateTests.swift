import XCTest
import SwiftData
@testable import MediaTracker

/// First-watch dates must be durable: a rewatch resets the *current projection*
/// (isWatched / watchedDate) but must never move the original first-watch date.
@MainActor
final class FirstWatchedDateTests: MTTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
            WatchCycle.self, WatchEvent.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// The `state` setter defers a `syncCachedProperties` onto the main actor.
    /// Without letting it drain, it can run after the in-memory container is
    /// gone and trap inside SwiftData — so any test that assigns `item.state`
    /// must await this before returning.
    private func settleDeferredSync() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    /// Builds a show with one season of `episodeCount` episodes, all unwatched.
    private func makeShow(
        in context: ModelContext,
        id: String,
        tmdbID: Int,
        episodeCount: Int = 2
    ) -> (MediaItem, [TVEpisode]) {
        let item = MediaItem(id: id, title: "Show \(id)", overview: "", type: .tvShow)
        item.stateValue = "Active"
        let tv = TVShowDetails(tmdbID: tmdbID)
        tv.item = item
        item.tvShowDetails = tv
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: episodeCount, showID: tmdbID)
        season.tvShowDetails = tv
        tv.seasons.append(season)

        var episodes: [TVEpisode] = []
        for i in 1...episodeCount {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", showID: tmdbID)
            ep.season = season
            season.episodes.append(ep)
            episodes.append(ep)
        }

        context.insert(item)
        context.insert(tv)
        context.insert(season)
        episodes.forEach(context.insert)
        return (item, episodes)
    }

    // MARK: - Episode level

    func testFirstWatchIsRecordedOnFirstWatch() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, episodes) = makeShow(in: context, id: "tv_fw_1", tmdbID: 9101)
        try context.save()

        let before = Date().addingTimeInterval(-.days30)
        episodes[0].applyWatchedState(true, date: before, updatesInteractionDate: false)

        XCTAssertTrue(episodes[0].isWatched)
        XCTAssertEqual(episodes[0].firstWatchedDate, before)
        XCTAssertEqual(episodes[0].firstKnownWatchDate, before)
    }

    func testRewatchDoesNotMoveFirstWatchedDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, episodes) = makeShow(in: context, id: "tv_fw_2", tmdbID: 9102)
        try context.save()

        let original = Date().addingTimeInterval(-.days30)
        episodes[0].applyWatchedState(true, date: original, updatesInteractionDate: false)

        // Rewatch: projection cleared, then watched again a month later.
        episodes[0].markWatched(false, recordHistory: false)
        XCTAssertFalse(episodes[0].isWatched)
        XCTAssertNil(episodes[0].watchedDate)
        XCTAssertEqual(episodes[0].firstWatchedDate, original, "unwatching must not erase the first-watch date")

        let rewatchDate = Date().addingTimeInterval(-.days2)
        episodes[0].applyWatchedState(true, date: rewatchDate, updatesInteractionDate: false)
        XCTAssertEqual(episodes[0].firstWatchedDate, original, "a later occurrence must not overwrite the first")
        XCTAssertEqual(episodes[0].watchedDate, rewatchDate, "the projection tracks the latest occurrence")
    }

    func testImportWithEarlierDateLowersFirstWatchedDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, episodes) = makeShow(in: context, id: "tv_fw_3", tmdbID: 9103)
        try context.save()

        let existing = Date().addingTimeInterval(-(10 * 86400))
        episodes[0].applyWatchedState(true, date: existing, updatesInteractionDate: false)
        let older = existing.addingTimeInterval(-.days30)
        episodes[0].applyImportedWatchState(watchedAt: older)

        XCTAssertEqual(episodes[0].firstWatchedDate, older, "restoring an older date keeps the true minimum")
    }

    func testFirstKnownWatchDateFallsBackForLegacyRows() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (_, episodes) = makeShow(in: context, id: "tv_fw_4", tmdbID: 9104)
        try context.save()

        // Simulate a row written before firstWatchedDate existed.
        let legacy = Date().addingTimeInterval(-.days7)
        episodes[0].isWatched = true
        episodes[0].watchedDate = legacy
        XCTAssertNil(episodes[0].firstWatchedDate)
        XCTAssertEqual(episodes[0].firstKnownWatchDate, legacy)
    }

    // MARK: - Rewatch cycle integration

    func testStartingRewatchPreservesEpisodeFirstWatchedDates() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let previousContainer = DataService.modelContainer
        DataService.modelContainer = container
        defer { DataService.modelContainer = previousContainer }

        let (item, episodes) = makeShow(in: context, id: "tv_fw_5", tmdbID: 9105)
        let original = Date().addingTimeInterval(-(60 * 86400))
        for ep in episodes { ep.applyWatchedState(true, date: original, updatesInteractionDate: false) }
        try context.save()

        item.state = .rewatching
        item.syncCachedProperties(now: Date())
        try context.save()

        XCTAssertEqual(item.state, .rewatching)
        XCTAssertEqual(item.rewatchCount, 1)
        for ep in episodes {
            XCTAssertFalse(ep.isWatched, "the projection is reset for the new cycle")
            XCTAssertEqual(ep.firstWatchedDate, original, "first-watch date survives into the rewatch")
        }
        await settleDeferredSync()
    }

    func testBulkCompleteAfterRewatchKeepsOriginalFirstWatchedDates() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let previousContainer = DataService.modelContainer
        DataService.modelContainer = container
        defer { DataService.modelContainer = previousContainer }

        let (item, episodes) = makeShow(in: context, id: "tv_fw_6", tmdbID: 9106)
        let original = Date().addingTimeInterval(-(60 * 86400))
        for ep in episodes { ep.applyWatchedState(true, date: original, updatesInteractionDate: false) }
        item.state = .completed
        try context.save()

        // Begin a rewatch, then complete the show without rewatching every episode.
        item.state = .rewatching
        item.syncCachedProperties(now: Date())
        try context.save()

        // Re-watch only the first episode, then bulk-mark the rest as the app does.
        episodes[0].markWatched(true, recordHistory: false)
        for ep in episodes.dropFirst() { ep.markWatched(true, recordHistory: false) }
        try context.save()

        for ep in episodes {
            XCTAssertTrue(ep.isWatched)
            XCTAssertEqual(
                ep.firstWatchedDate, original,
                "bulk-completing a rewatch must not restamp the original first watch"
            )
        }
        await settleDeferredSync()
    }

    /// A rewatch clears `isWatched`, so the backfill must be driven by the event
    /// ledger rather than the current projection — otherwise episodes still
    /// waiting in the new cycle lose their original date and get stamped with
    /// the rewatch date when they are eventually watched.
    func testBackfillRecoversFirstWatchDateForUnwatchedProjection() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let previousContainer = DataService.modelContainer
        DataService.modelContainer = container
        defer { DataService.modelContainer = previousContainer }

        let item = MediaItem(id: "tv_fw_8", title: "Show", overview: "", type: .tvShow)
        item.stateValue = MediaState.rewatching.rawValue
        let tv = TVShowDetails(tmdbID: 9108)
        tv.item = item
        item.tvShowDetails = tv
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 2, showID: 9108)
        season.tvShowDetails = tv
        tv.seasons.append(season)

        var episodes: [TVEpisode] = []
        for i in 1...2 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", showID: 9108)
            ep.season = season
            season.episodes.append(ep)
            episodes.append(ep)
        }
        context.insert(item)
        context.insert(tv)
        context.insert(season)
        episodes.forEach(context.insert)
        try context.save()

        // The original watch, recorded in the first-watch cycle.
        let original = Date().addingTimeInterval(-(400 * 86400))
        let cycle = WatchCycle(mediaID: item.id, kind: .tvShow, startedAt: original, state: .completed, isComplete: true)
        context.insert(cycle)
        for ep in episodes {
            let episodeID = try XCTUnwrap(ep.uniqueID)
            context.insert(WatchEvent(
                cycleID: cycle.id,
                mediaID: item.id,
                episodeID: episodeID,
                watchedAt: original,
                deduplicationKey: "\(cycle.id.uuidString):\(episodeID)"
            ))
        }
        try context.save()

        // Rewatch started: the projection is cleared, dates are gone.
        for ep in episodes {
            ep.markWatched(false, recordHistory: false)
        }
        try context.save()
        for ep in episodes {
            XCTAssertFalse(ep.isWatched)
            XCTAssertNil(ep.watchedDate)
            XCTAssertNil(ep.firstWatchedDate)
        }

        UserDefaults.standard.set(0, forKey: "firstWatchedDateBackfillVersion")
        await DatabaseMigrations.runFirstWatchedDateBackfillIfNeeded(container: container)

        // The migration runs in its own ModelContext, so assert against a fresh
        // fetch rather than the objects this test already holds.
        let verifyContext = ModelContext(container)
        let healedEpisodes = try verifyContext.fetch(FetchDescriptor<TVEpisode>())
        XCTAssertEqual(healedEpisodes.count, 2)
        for ep in healedEpisodes {
            XCTAssertEqual(
                ep.firstWatchedDate, original,
                "the backfill must recover the date even while the episode is unwatched in the current cycle"
            )
        }
        let healedItem = try XCTUnwrap(try verifyContext.fetch(FetchDescriptor<MediaItem>()).first)
        XCTAssertEqual(healedItem.firstWatchedAt, original)
    }

    /// A sync that lands before the backfill must not pin a title's first-watch
    /// date to the current rewatch date, and the backfill must be able to lower
    /// a value that was already pinned that way.
    func testTitleFirstWatchedAtIgnoresProjectionAndBackfillLowersIt() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let previousContainer = DataService.modelContainer
        DataService.modelContainer = container
        defer { DataService.modelContainer = previousContainer }

        let item = MediaItem(id: "tv_fw_9", title: "Show", overview: "", type: .tvShow)
        item.stateValue = MediaState.rewatching.rawValue
        let tv = TVShowDetails(tmdbID: 9109)
        tv.item = item
        item.tvShowDetails = tv
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 2, showID: 9109)
        season.tvShowDetails = tv
        tv.seasons.append(season)

        var episodes: [TVEpisode] = []
        for i in 1...2 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", showID: 9109)
            ep.season = season
            season.episodes.append(ep)
            episodes.append(ep)
        }
        context.insert(item)
        context.insert(tv)
        context.insert(season)
        episodes.forEach(context.insert)
        try context.save()

        // Mid-rewatch: one episode already rewatched, carrying only the
        // projection date, and no durable episode dates yet.
        let rewatchDate = Date()
        episodes[0].markWatched(true, recordHistory: false)
        item.syncCachedProperties(now: Date())
        XCTAssertNil(
            item.firstWatchedAt,
            "a title must not take its first-watch date from the current projection"
        )

        // The ledger has the real original dates.
        let original = Date().addingTimeInterval(-(500 * 86400))
        let firstCycle = WatchCycle(
            mediaID: item.id,
            kind: .tvShow,
            startedAt: original,
            state: .completed,
            isComplete: true
        )
        let rewatchCycle = WatchCycle(
            mediaID: item.id,
            kind: .tvShow,
            startedAt: rewatchDate,
            state: .active,
            isRewatch: true,
            scopeEpisodeIDs: [try XCTUnwrap(episodes[0].uniqueID)]
        )
        context.insert(firstCycle)
        context.insert(rewatchCycle)
        for ep in episodes {
            let episodeID = try XCTUnwrap(ep.uniqueID)
            context.insert(WatchEvent(
                cycleID: firstCycle.id,
                mediaID: item.id,
                episodeID: episodeID,
                watchedAt: original,
                deduplicationKey: "\(firstCycle.id.uuidString):\(episodeID)"
            ))
        }
        try context.save()

        // Something pinned the title to the rewatch date before the migration ran.
        item.firstWatchedAt = rewatchDate
        try context.save()

        UserDefaults.standard.set(1, forKey: "firstWatchedDateBackfillVersion")
        await DatabaseMigrations.runFirstWatchedDateBackfillIfNeeded(container: container)

        let verifyContext = ModelContext(container)
        let healedItem = try XCTUnwrap(try verifyContext.fetch(FetchDescriptor<MediaItem>()).first)
        XCTAssertEqual(
            healedItem.firstWatchedAt, original,
            "the backfill must lower a first-watch date that was pinned to a rewatch"
        )
        XCTAssertEqual(
            healedItem.rewatchCount, 1,
            "rewatch counts predate the field, so they are derived from existing cycles"
        )
    }

    // MARK: - Title level

    func testShowInheritsFirstWatchedAtFromEarliestEpisode() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let (item, episodes) = makeShow(in: context, id: "tv_fw_7", tmdbID: 9107)
        try context.save()

        let later = Date().addingTimeInterval(-(20 * 86400))
        let earlier = later.addingTimeInterval(-(10 * 86400))
        episodes[1].applyWatchedState(true, date: later, updatesInteractionDate: false)
        episodes[0].applyWatchedState(true, date: earlier, updatesInteractionDate: false)

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.firstWatchedAt, earlier)
    }

    func testMovieRecordsFirstWatchOnCompletionAndKeepsItAcrossRewatch() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let previousContainer = DataService.modelContainer
        DataService.modelContainer = container
        defer { DataService.modelContainer = previousContainer }

        let movie = MediaItem(id: "mv_fw_1", title: "Movie", overview: "", type: .movie)
        context.insert(movie)
        try context.save()

        movie.state = .completed
        let firstCompletion = movie.firstWatchedAt
        XCTAssertNotNil(firstCompletion)

        // Rewatch: completed -> re-watching -> completed again.
        movie.state = .rewatching
        movie.state = .completed
        XCTAssertEqual(movie.firstWatchedAt, firstCompletion, "a rewatch must not move the first-watch date")
        XCTAssertEqual(movie.rewatchCount, 1)
        await settleDeferredSync()
    }
}
