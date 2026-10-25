import XCTest
import SwiftData
@testable import MediaTracker

/// A title the user marked Completed must survive a background recount.
///
/// Before this, `syncTVProperties` auto-advanced away from `.completed` on any
/// recount, so two ordinary situations silently rewrote the user's state:
///   • a show set to Completed before its episodes were fetched recounted as 0/N
///     and became Wishlist;
///   • a Completed show that gained a season recounted as N/(N+1) and became Active.
/// Only a *user edit* of an episode's watched state may move a title out of Completed.
final class CompletedStateStickinessTests: MTTestCase {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: MediaItem.self, TVShowDetails.self, TVSeason.self,
                SeasonCastMember.self, TVEpisode.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @discardableResult
    private func makeShow(
        in context: ModelContext,
        episodes: Int,
        watched: Int = 0
    ) -> MediaItem {
        let item = MediaItem(id: "tv_1", title: "Show", overview: "", type: .tvShow)
        context.insert(item)

        let details = TVShowDetails(tmdbID: 1)
        details.item = item
        item.tvShowDetails = details
        context.insert(details)

        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: episodes, showID: 1)
        season.tvShowDetails = details
        details.seasons.append(season)
        context.insert(season)

        for number in 1...max(1, episodes) {
            let episode = TVEpisode(
                episodeNumber: number,
                seasonNumber: 1,
                name: "E\(number)",
                overview: "",
                airDate: nil,
                runtime: 40,
                isWatched: number <= watched,
                showID: 1
            )
            episode.season = season
            season.episodes.append(episode)
            context.insert(episode)
        }
        return item
    }

    @MainActor
    func testBackgroundRecountDoesNotDemoteCompletedToWishlist() throws {
        // Keep the container alive: a ModelContext does not retain it.
        let container = try makeContainer()
        let context = container.mainContext
        let item = makeShow(in: context, episodes: 3, watched: 0)
        item.stateValue = MediaState.completed.rawValue

        // Episode backfill arrives after the user marked it completed: 0 of 3.
        item.syncCachedProperties(dirty: [.progress], userEditedWatchState: false)

        XCTAssertEqual(item.state, .completed)
        XCTAssertEqual(item.cachedWatchedEpisodeCount, 0)
    }

    @MainActor
    func testBackgroundRecountDoesNotDemoteCompletedToActive() throws {
        // Keep the container alive: a ModelContext does not retain it.
        let container = try makeContainer()
        let context = container.mainContext
        let item = makeShow(in: context, episodes: 4, watched: 3)
        item.stateValue = MediaState.completed.rawValue

        // A season was added, so the show now recounts as 3 of 4.
        item.syncCachedProperties(dirty: [.progress], userEditedWatchState: false)

        XCTAssertEqual(item.state, .completed)
    }

    @MainActor
    func testUserUnmarkingAnEpisodeStillMovesCompletedToActive() throws {
        // Keep the container alive: a ModelContext does not retain it.
        let container = try makeContainer()
        let context = container.mainContext
        let item = makeShow(in: context, episodes: 4, watched: 3)
        item.stateValue = MediaState.completed.rawValue

        // The user unmarked an episode; TVTrackingView recounts with
        // userEditedWatchState: true.
        item.syncCachedProperties(dirty: [.progress], userEditedWatchState: true)

        XCTAssertEqual(item.state, .active)
    }

    @MainActor
    func testWishlistStillAutoAdvancesToCompletedAtFullProgress() throws {
        // Keep the container alive: a ModelContext does not retain it.
        let container = try makeContainer()
        let context = container.mainContext
        let item = makeShow(in: context, episodes: 3, watched: 3)
        item.stateValue = MediaState.wishlist.rawValue

        item.syncCachedProperties(dirty: [.progress], userEditedWatchState: false)

        XCTAssertEqual(item.state, .completed)
    }
}
