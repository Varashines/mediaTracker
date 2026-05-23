import XCTest
import SwiftData
@testable import MediaTracker

final class ProgressCalculationTests: XCTestCase {
    @MainActor
    func testFullProgressSingleSeason() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 1)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 3)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...3 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", runtime: 30)
            ep.season = season
            season.episodes.append(ep)
            context.insert(ep)
        }

        try context.save()

        let result = tv.calculateProgress(forceRecalculate: true)
        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.watchedCount, 0)
        XCTAssertEqual(result.totalRuntime, 0)
    }

    @MainActor
    func testPartialWatchProgress() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "2", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 2)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 5)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...5 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", runtime: 30 + i)
            ep.season = season
            season.episodes.append(ep)
            context.insert(ep)
        }

        try context.save()

        let episodes = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
        episodes[0].markWatched(true)
        episodes[1].markWatched(true)
        episodes[2].markWatched(true)

        let result = tv.calculateProgress(forceRecalculate: true)
        XCTAssertEqual(result.totalCount, 5)
        XCTAssertEqual(result.watchedCount, 3)
        XCTAssertEqual(result.remainingCount, 0)
        XCTAssertEqual(result.firstUnwatched?.episodeNumber, 4)
    }

    @MainActor
    func testRemainingEpisodesOnlyCountsAired() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "3", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 3)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 4)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let yesterday = Date().addingTimeInterval(-86400)
        let tomorrow = Date().addingTimeInterval(86400)

        for i in 1...4 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "")
            ep.season = season
            ep.airDateValue = i <= 2 ? yesterday : tomorrow
            season.episodes.append(ep)
            context.insert(ep)
            if i <= 1 { ep.markWatched(true) }
        }

        try context.save()

        let result = tv.calculateProgress(forceRecalculate: true)
        XCTAssertEqual(result.totalCount, 4)
        XCTAssertEqual(result.watchedCount, 1)
        XCTAssertEqual(result.remainingCount, 1)
    }

    @MainActor
    func testSpecialsExcluded() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "4", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 4)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season0 = TVSeason(seasonNumber: 0, name: "Specials", episodeCount: 2)
        season0.tvShowDetails = tv
        tv.seasons.append(season0)
        context.insert(season0)

        let season1 = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 3)
        season1.tvShowDetails = tv
        tv.seasons.append(season1)
        context.insert(season1)

        for i in 1...2 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 0, name: "Special \(i)", overview: "")
            ep.season = season0
            season0.episodes.append(ep)
            context.insert(ep)
            ep.markWatched(true)
        }
        for i in 1...3 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "")
            ep.season = season1
            season1.episodes.append(ep)
            context.insert(ep)
        }

        try context.save()

        let result = tv.calculateProgress(forceRecalculate: true)
        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.watchedCount, 0)
    }

    @MainActor
    func testCachedResultUsedWhenAvailable() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "5", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 5)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 3)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...3 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "")
            ep.season = season
            season.episodes.append(ep)
            context.insert(ep)
            ep.markWatched(true)
        }

        try context.save()

        tv.totalEpisodesCount = 3
        tv.watchedEpisodesCount = 3
        tv.remainingEpisodesCount = 0

        let result = tv.calculateProgress(forceRecalculate: false)
        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.watchedCount, 3)
        XCTAssertEqual(result.remainingCount, 0)
    }

    @MainActor
    func testMultiSeasonProgress() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "6", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 6)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)

        for s in 1...2 {
            let season = TVSeason(seasonNumber: s, name: "S\(s)", episodeCount: 3)
            season.tvShowDetails = tv
            tv.seasons.append(season)
            context.insert(season)
            for e in 1...3 {
                let ep = TVEpisode(episodeNumber: e, seasonNumber: s, name: "S\(s)E\(e)", overview: "")
                ep.season = season
                season.episodes.append(ep)
                context.insert(ep)
                if s == 1 { ep.markWatched(true) }
            }
        }

        try context.save()

        let result = tv.calculateProgress(forceRecalculate: true)
        XCTAssertEqual(result.totalCount, 6)
        XCTAssertEqual(result.watchedCount, 3)
        XCTAssertEqual(result.firstUnwatched?.episodeNumber, 1)
        XCTAssertEqual(result.firstUnwatched?.seasonNumber, 2)
    }

    @MainActor
    func testRemainingEpisodesCountForFutureEpisodes() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "7", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 7)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 3)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let now = Date()
        for i in 1...3 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "")
            ep.season = season
            // Episodes 1 and 2 have aired, episode 3 airs in future
            ep.airDateValue = i <= 2 ? now.addingTimeInterval(-86400 * Double(3 - i)) : now.addingTimeInterval(86400 * 7)
            season.episodes.append(ep)
            context.insert(ep)
            ep.markWatched(i <= 1) // only episode 1 watched
        }

        try context.save()

        // aired = 2 (eps 1 and 2), watched = 1 → remaining = 1
        let result = tv.calculateProgress(forceRecalculate: true)
        XCTAssertEqual(result.remainingCount, 1)
        XCTAssertEqual(tv.remainingEpisodesCount, 1)
    }

    @MainActor
    func testForceRecalculateIgnoresCache() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "8", title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 8)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 2)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...2 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "")
            ep.season = season
            season.episodes.append(ep)
            context.insert(ep)
        }

        try context.save()

        tv.totalEpisodesCount = 999
        tv.watchedEpisodesCount = 999

        let cached = tv.calculateProgress(forceRecalculate: false)
        XCTAssertEqual(cached.totalCount, 999)

        let forced = tv.calculateProgress(forceRecalculate: true)
        XCTAssertEqual(forced.totalCount, 2)
        XCTAssertEqual(forced.watchedCount, 0)
    }
}
