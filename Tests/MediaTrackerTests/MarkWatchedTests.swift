import XCTest
import SwiftData
@testable import MediaTracker

final class MarkWatchedTests: XCTestCase {
    @MainActor
    func testMarkWatchedSetsProperties() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 1)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let ep = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "E1", overview: "")
        ep.season = season
        season.episodes.append(ep)
        context.insert(ep)

        try context.save()

        ep.markWatched(true)
        XCTAssertTrue(ep.isWatched)
        XCTAssertNotNil(ep.lastWatchedDate)
        XCTAssertEqual(season.watchedEpisodesCount, 1)
        XCTAssertEqual(tv.watchedEpisodesCount, 1)

        ep.markWatched(false)
        XCTAssertFalse(ep.isWatched)
        XCTAssertNil(ep.lastWatchedDate)
        XCTAssertEqual(season.watchedEpisodesCount, 0)
        XCTAssertEqual(tv.watchedEpisodesCount, 0)
    }

    @MainActor
    func testMarkWatchedUpdatesRuntime() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "2", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 2)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let ep = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "E1", overview: "", runtime: 45)
        ep.season = season
        season.episodes.append(ep)
        context.insert(ep)

        try context.save()

        XCTAssertNil(item.cachedRuntime)

        ep.markWatched(true)
        XCTAssertEqual(item.cachedRuntime, 45)

        ep.markWatched(false)
        XCTAssertEqual(item.cachedRuntime, 0)

        ep.markWatched(true)
        XCTAssertEqual(item.cachedRuntime, 45)
    }

    @MainActor
    func testMarkWatchedUpdatesRemainingForAiredEpisode() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "3", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 3)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

        let airedEp = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Aired", overview: "", airDate: "2026-01-01")
        airedEp.season = season
        airedEp.airDateValue = yesterday
        season.episodes.append(airedEp)
        context.insert(airedEp)

        let futureEp = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Future", overview: "", airDate: "2026-06-01")
        futureEp.season = season
        futureEp.airDateValue = tomorrow
        season.episodes.append(futureEp)
        context.insert(futureEp)

        tv.remainingEpisodesCount = 2
        try context.save()

        airedEp.markWatched(true)
        XCTAssertEqual(tv.remainingEpisodesCount, 1)

        futureEp.markWatched(true)
        XCTAssertEqual(tv.remainingEpisodesCount, 1)

        airedEp.markWatched(false)
        XCTAssertEqual(tv.remainingEpisodesCount, 2)
    }

    @MainActor
    func testDoubleMarkWatchedIsNoOp() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "4", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 4)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let ep = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "E1", overview: "")
        ep.season = season
        season.episodes.append(ep)
        context.insert(ep)

        try context.save()

        ep.markWatched(true)
        XCTAssertEqual(season.watchedEpisodesCount, 1)
        XCTAssertEqual(tv.watchedEpisodesCount, 1)
        let lastDate = ep.lastWatchedDate

        ep.markWatched(true)
        XCTAssertEqual(season.watchedEpisodesCount, 1)
        XCTAssertEqual(tv.watchedEpisodesCount, 1)
        XCTAssertEqual(ep.lastWatchedDate, lastDate)

        ep.markWatched(false)
        XCTAssertEqual(season.watchedEpisodesCount, 0)
        XCTAssertEqual(tv.watchedEpisodesCount, 0)

        ep.markWatched(false)
        XCTAssertEqual(season.watchedEpisodesCount, 0)
        XCTAssertEqual(tv.watchedEpisodesCount, 0)
    }
}
