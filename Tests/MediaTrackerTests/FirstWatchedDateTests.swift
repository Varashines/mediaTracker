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

    func testStartingRewatchPreservesEpisodeFirstWatchedDates() throws {
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
    }

    func testBulkCompleteAfterRewatchKeepsOriginalFirstWatchedDates() throws {
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

    func testMovieRecordsFirstWatchOnCompletionAndKeepsItAcrossRewatch() throws {
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
    }
}
