import XCTest
import SwiftData
@testable import MediaTracker

final class WeeklyDigestTests: XCTestCase {
    private func makeContainer() -> ModelContainer {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            SeasonCastMember.self, TVEpisode.self, CastMember.self,
            MediaCollection.self, StudioAliasEntity.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @MainActor
    private func makeItem(id: String, title: String, type: MediaType, state: String) -> MediaItem {
        let item = MediaItem(id: id, title: title, overview: "", type: type)
        item.stateValue = state
        return item
    }

    @MainActor
    private func makeEpisode(showID: Int, watchedAt: Date, episodeNumber: Int = 1) -> TVEpisode {
        let episode = TVEpisode(
            episodeNumber: episodeNumber, seasonNumber: 1,
            name: "Ep", overview: "",
            isWatched: true, showID: showID
        )
        episode.watchedDate = watchedAt
        return episode
    }

    @MainActor
    func testCountsShowsAndMoviesInWindow() async {
        let container = makeContainer()
        let context = container.mainContext

        context.insert(makeItem(id: "tv_1", title: "Show A", type: .tvShow, state: "Active"))
        context.insert(makeEpisode(showID: 1, watchedAt: date(2026, 8, 10)))
        context.insert(makeEpisode(showID: 1, watchedAt: date(2026, 8, 11), episodeNumber: 2))
        context.insert(makeItem(id: "tv_2", title: "Show B", type: .tvShow, state: "Active"))
        context.insert(makeEpisode(showID: 2, watchedAt: date(2026, 8, 12)))

        let movie = makeItem(id: "movie_3", title: "Movie A", type: .movie, state: "Completed")
        movie.lastStateChangeDate = date(2026, 8, 12)
        context.insert(movie)
        try? context.save()

        let digest = await WeeklyDigestService(modelContainer: container).digest(endingAt: date(2026, 8, 12))

        XCTAssertEqual(digest.shows, 2)
        XCTAssertEqual(digest.movies, 1)
        XCTAssertEqual(digest.topShows, ["Show A", "Show B"])
    }

    @MainActor
    func testExcludesOutsideWindowAndSpecials() async {
        let container = makeContainer()
        let context = container.mainContext

        context.insert(makeItem(id: "tv_1", title: "Old Show", type: .tvShow, state: "Active"))
        let old = makeEpisode(showID: 1, watchedAt: date(2026, 8, 1))
        context.insert(old)

        context.insert(makeItem(id: "tv_2", title: "Special Show", type: .tvShow, state: "Active"))
        let special = makeEpisode(showID: 2, watchedAt: date(2026, 8, 12))
        special.seasonNumber = 0
        special.uniqueID = "2_0_1"
        context.insert(special)

        let movie = makeItem(id: "movie_3", title: "Old Movie", type: .movie, state: "Completed")
        movie.lastStateChangeDate = date(2026, 8, 1)
        context.insert(movie)
        try? context.save()

        let digest = await WeeklyDigestService(modelContainer: container).digest(endingAt: date(2026, 8, 12))

        XCTAssertEqual(digest.shows, 0) // specials + out-of-window excluded
        XCTAssertEqual(digest.movies, 0)
        XCTAssertTrue(digest.topShows.isEmpty)
    }

    @MainActor
    func testEmptyWeek() async {
        let container = makeContainer()
        let context = container.mainContext
        try? context.save()

        let digest = await WeeklyDigestService(modelContainer: container).digest(endingAt: date(2026, 8, 12))

        XCTAssertEqual(digest.shows, 0)
        XCTAssertEqual(digest.movies, 0)
    }
}
