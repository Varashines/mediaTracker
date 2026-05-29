import XCTest
import SwiftData
@testable import MediaTracker

final class StateTransitionTests: XCTestCase {
    @MainActor
    func testSyncCompletesShowFromActive() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Show", overview: "", type: .tvShow)
        item.stateValue = "Active"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 1)
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
            ep.markWatched(true)
        }

        try context.save()

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .completed)
    }

    @MainActor
    func testSyncDoesNotCompleteRewatching() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "2", title: "Show", overview: "", type: .tvShow)
        item.stateValue = "Re-watching"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 2)
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
            ep.markWatched(true)
        }

        try context.save()

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .rewatching)
    }

    @MainActor
    func testSyncActivatesFromWishlist() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "3", title: "Show", overview: "", type: .tvShow)
        item.stateValue = "Wishlist"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 3)
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
            if i == 1 { ep.markWatched(true) }
        }

        try context.save()

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .active)
    }

    @MainActor
    func testSyncDoesNotTransitionToActiveFromOnHold() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "9", title: "Show", overview: "", type: .tvShow)
        item.stateValue = MediaState.onHold.rawValue
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 9)
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
            if i == 1 { ep.markWatched(true) }
        }

        try context.save()

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .onHold)
    }

    @MainActor
    func testCheckOverallCompletionCompletesShow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "4", title: "Show", overview: "", type: .tvShow)
        item.stateValue = "Active"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 4)
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
            ep.markWatched(true)
        }

        try context.save()

        tv.totalEpisodesCount = 2
        tv.watchedEpisodesCount = 2

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .completed)
    }

    @MainActor
    func testCheckOverallCompletionDoesNotOverrideRewatching() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "5", title: "Show", overview: "", type: .tvShow)
        item.stateValue = "Re-watching"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 5)
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
            ep.markWatched(true)
        }

        try context.save()

        tv.totalEpisodesCount = 2
        tv.watchedEpisodesCount = 2

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .rewatching)
    }

    @MainActor
    func testCheckOverallCompletionActivatesFromWishlist() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "6", title: "Show", overview: "", type: .tvShow)
        item.stateValue = "Wishlist"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 6)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 2)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let ep = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep 1", overview: "")
        ep.season = season
        season.episodes.append(ep)
        context.insert(ep)
        ep.markWatched(true)

        try context.save()

        tv.totalEpisodesCount = 2
        tv.watchedEpisodesCount = 1

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .active)
    }

    @MainActor
    func testCheckOverallCompletionRevertsToWishlist() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "7", title: "Show", overview: "", type: .tvShow)
        item.stateValue = "Active"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 7)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 2)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let ep = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep 1", overview: "")
        ep.season = season
        season.episodes.append(ep)
        context.insert(ep)
        ep.markWatched(false)

        try context.save()

        tv.totalEpisodesCount = 2
        tv.watchedEpisodesCount = 0

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .wishlist)
    }

    @MainActor
    func testCheckOverallCompletionNoChangeForOnHold() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "8", title: "Show", overview: "", type: .tvShow)
        item.stateValue = MediaState.onHold.rawValue
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 8)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 2)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let ep = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep 1", overview: "")
        ep.season = season
        season.episodes.append(ep)
        context.insert(ep)
        ep.markWatched(true)

        try context.save()

        tv.totalEpisodesCount = 2
        tv.watchedEpisodesCount = 1

        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .onHold)
    }

    @MainActor
    func testAvailableStates() {
        let fullProgress: [MediaState] = MediaItem.availableStates(for: .tvShow, progress: 1.0)
        XCTAssertEqual(fullProgress, [.completed, .rewatching])

        let partialProgress: [MediaState] = MediaItem.availableStates(for: .tvShow, progress: 0.5)
        XCTAssertEqual(partialProgress, [.active, .onHold, .dropped, .rewatching, .completed])

        let noProgress: [MediaState] = MediaItem.availableStates(for: .tvShow, progress: 0)
        XCTAssertEqual(noProgress, MediaState.allCases)
    }

    @MainActor
    func testRecalculateHealsDriftAndCompletesShow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "heal_drift", title: "Show", overview: "", type: .tvShow)
        item.stateValue = "Active"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 1000)
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
            ep.markWatched(true)
        }

        try context.save()

        // Simulate drift where cached/denormalized counts are completely wrong (due to duplicate mutations)
        tv.watchedEpisodesCount = 1 // But we marked 2 as watched!
        tv.totalEpisodesCount = 2

        // Verify that recalculateCachedProperties(force: true) corrects the drift
        tv.recalculateCachedProperties(triggerSync: true, force: true)
        XCTAssertEqual(tv.watchedEpisodesCount, 2)
        XCTAssertEqual(tv.totalEpisodesCount, 2)

        // Verify overall completion transitions the state to completed
        item.syncCachedProperties(now: Date())
        XCTAssertEqual(item.state, .completed)
    }
}
