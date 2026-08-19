import XCTest
import SwiftData
@testable import MediaTracker

final class YearInReviewTests: XCTestCase {
    private func makeContainer() throws -> (container: ModelContainer, directory: URL) {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            SeasonCastMember.self, TVEpisode.self, CastMember.self,
            MediaCollection.self, StudioAliasEntity.self
        ])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaTracker-YearReview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: directory.appendingPathComponent("review.sqlite"))
        do {
            return (try ModelContainer(for: schema, configurations: [config]), directory)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @MainActor
    private func makeItem(id: String, title: String, type: MediaType, releaseDate: Date?, state: String) -> MediaItem {
        let item = MediaItem(id: id, title: title, overview: "", type: type)
        item.releaseDate = releaseDate
        item.stateValue = state
        return item
    }

    @MainActor
    private func makeEpisode(showID: Int, watchedAt: Date, runtime: Int, episodeNumber: Int = 1) -> TVEpisode {
        let episode = TVEpisode(
            episodeNumber: episodeNumber, seasonNumber: 1,
            name: "Ep", overview: "",
            runtime: runtime, isWatched: true, showID: showID
        )
        episode.watchedDate = watchedAt
        return episode
    }

    @MainActor
    func testReleased2026AndWatchedOnly() async throws {
        let fixture = try makeContainer()
        let container = fixture.container
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let context = container.mainContext

        let in2026 = makeItem(id: "movie_1", title: "2026 Flick", type: .movie, releaseDate: date(2026, 1, 15), state: "Completed")
        let old = makeItem(id: "movie_2", title: "2025 Flick", type: .movie, releaseDate: date(2025, 1, 15), state: "Completed")
        let unwatched = makeItem(id: "movie_3", title: "Unwatched", type: .movie, releaseDate: date(2026, 2, 1), state: "Wishlist")
        let noDate = makeItem(id: "movie_4", title: "No Date", type: .movie, releaseDate: nil, state: "Completed")
        context.insert(in2026)
        context.insert(old)
        context.insert(unwatched)
        context.insert(noDate)
        try? context.save()

        let review = await YearInReviewService(modelContainer: container).compute(year: 2026)

        let allTitles = review.titlesByDay.values.flatMap { $0 }.map(\.title)
        XCTAssertTrue(allTitles.contains("2026 Flick"))
        XCTAssertTrue(allTitles.contains("2025 Flick")) // completed this year
        XCTAssertFalse(allTitles.contains("Unwatched"))
        XCTAssertTrue(allTitles.contains("No Date"))    // release date irrelevant
    }

    @MainActor
    func testTVShowsWatched2026AppearInTitlesByDay() async throws {
        let fixture = try makeContainer()
        let container = fixture.container
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let context = container.mainContext

        let show = makeItem(id: "tv_100", title: "2026 Show", type: .tvShow, releaseDate: date(2026, 3, 1), state: "Active")
        context.insert(show)
        context.insert(makeEpisode(showID: 100, watchedAt: date(2026, 3, 10), runtime: 45))
        try? context.save()

        let review = await YearInReviewService(modelContainer: container).compute(year: 2026)

        let titles = review.titlesByDay[Calendar.current.startOfDay(for: date(2026, 3, 10))] ?? []
        XCTAssertEqual(titles.map(\.title), ["2026 Show"])
    }

    @MainActor
    func testHeatmapAggregationPerDay() async throws {
        let fixture = try makeContainer()
        let container = fixture.container
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let context = container.mainContext

        context.insert(makeEpisode(showID: 5, watchedAt: date(2026, 3, 3), runtime: 45))
        context.insert(makeEpisode(showID: 5, watchedAt: date(2026, 3, 3), runtime: 45, episodeNumber: 2))
        context.insert(makeEpisode(showID: 6, watchedAt: date(2026, 3, 5), runtime: 60))

        let movie = makeItem(id: "movie_9", title: "March Movie", type: .movie, releaseDate: date(2026, 1, 1), state: "Completed")
        movie.cachedRuntime = 120
        movie.lastStateChangeDate = date(2026, 3, 3)
        context.insert(movie)
        try? context.save()

        let review = await YearInReviewService(modelContainer: container).compute(year: 2026)

        let day3 = review.activityByDay[Calendar.current.startOfDay(for: date(2026, 3, 3))]
        XCTAssertEqual(day3?.minutes, 210)
        XCTAssertEqual(day3?.episodes, 2)
        XCTAssertEqual(day3?.movies, 1)

        let day5 = review.activityByDay[Calendar.current.startOfDay(for: date(2026, 3, 5))]
        XCTAssertEqual(day5?.minutes, 60)
        XCTAssertEqual(day5?.episodes, 1)

        XCTAssertEqual(review.totalMinutes, 270)
        XCTAssertEqual(review.totalEpisodes, 3)
        XCTAssertEqual(review.totalMovies, 1)
        XCTAssertEqual(review.totalDaysWatched, 2)
        XCTAssertEqual(review.busiestDay?.minutes, 210)
    }

    @MainActor
    func testYearScopingExcludesOutsideWindow() async throws {
        let fixture = try makeContainer()
        let container = fixture.container
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let context = container.mainContext

        context.insert(makeEpisode(showID: 7, watchedAt: date(2025, 12, 31), runtime: 45))

        let movie = makeItem(id: "movie_10", title: "Jan Movie", type: .movie, releaseDate: date(2026, 1, 1), state: "Completed")
        movie.lastStateChangeDate = date(2026, 1, 1)
        context.insert(movie)
        try? context.save()

        let review = await YearInReviewService(modelContainer: container).compute(year: 2026)

        XCTAssertEqual(review.totalEpisodes, 0)
        XCTAssertEqual(review.totalMovies, 1)
    }

    @MainActor
    func testTasteOverWatchedIn2026WithoutCutoffs() async throws {
        let fixture = try makeContainer()
        let container = fixture.container
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let context = container.mainContext

        // Six loved, completed, Sci-Fi movies watched in 2026 → taste scores without cutoff floors.
        for i in 0..<6 {
            let movie = makeItem(id: "movie_\(i)", title: "2026 Sci-Fi \(i)", type: .movie, releaseDate: date(2026, 1, 1), state: "Completed")
            movie.tasteValue = "Love"
            movie.cachedGenres = ["Sci-Fi"]
            movie.cachedNetwork = "Netflix"
            movie.cachedLanguage = "ko"
            movie.storedCast = [
                SimpleCastMember(id: "a\(i)", name: "Actor A", characterName: "Role", profileURL: nil, order: 0),
                SimpleCastMember(id: "b\(i)", name: "Actor B", characterName: "Role", profileURL: nil, order: 1)
            ]
            context.insert(movie)
        }
        // A loved Romance movie completed in 2025 must NOT influence the 2026 taste.
        let romance = makeItem(id: "movie_old", title: "2025 Romance", type: .movie, releaseDate: date(2025, 5, 1), state: "Completed")
        romance.tasteValue = "Love"
        romance.cachedGenres = ["Romance"]
        romance.lastStateChangeDate = date(2025, 6, 1)
        context.insert(romance)
        try? context.save()

        let review = await YearInReviewService(modelContainer: container).compute(year: 2026)

        XCTAssertEqual(review.totalMovies, 6)
        XCTAssertEqual(review.topGenres.map(\.name), ["Sci-Fi"])
        XCTAssertFalse(review.topGenres.contains { $0.name == "Romance" })
        XCTAssertEqual(review.topNetworks.map(\.name), ["Netflix"])
        XCTAssertEqual(review.topLanguages.map(\.name), ["Korean"])
        XCTAssertEqual(review.topActors.map(\.name), ["Actor A", "Actor B"])
    }

    @MainActor
    func testSeasonZeroSpecialsExcluded() async throws {
        let fixture = try makeContainer()
        let container = fixture.container
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let context = container.mainContext

        let show = makeItem(id: "tv_50", title: "Specials Show", type: .tvShow, releaseDate: date(2026, 1, 1), state: "Completed")
        context.insert(show)

        let s1 = makeEpisode(showID: 50, watchedAt: date(2026, 1, 5), runtime: 45, episodeNumber: 1)
        s1.seasonNumber = 1
        let s2 = makeEpisode(showID: 50, watchedAt: date(2026, 1, 5), runtime: 45, episodeNumber: 2)
        s2.seasonNumber = 1
        let special = makeEpisode(showID: 50, watchedAt: date(2026, 1, 5), runtime: 60, episodeNumber: 1)
        special.seasonNumber = 0
        special.uniqueID = "50_0_1"
        context.insert(s1)
        context.insert(s2)
        context.insert(special)
        try? context.save()

        let review = await YearInReviewService(modelContainer: container).compute(year: 2026)

        XCTAssertEqual(review.totalEpisodes, 2)
        XCTAssertEqual(review.totalMinutes, 90)
        let dayKey = Calendar.current.startOfDay(for: date(2026, 1, 5))
        let titles = review.titlesByDay[dayKey] ?? []
        XCTAssertEqual(titles.count, 1)
        XCTAssertEqual(titles.first?.episodeCount, 2)
    }

    @MainActor
    func testTitlesByDayIncludesMoviesAndShows() async throws {
        let fixture = try makeContainer()
        let container = fixture.container
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let context = container.mainContext

        let show = makeItem(id: "tv_60", title: "Day Show", type: .tvShow, releaseDate: date(2026, 1, 1), state: "Completed")
        context.insert(show)
        context.insert(makeEpisode(showID: 60, watchedAt: date(2026, 3, 10), runtime: 45, episodeNumber: 1))
        context.insert(makeEpisode(showID: 60, watchedAt: date(2026, 3, 10), runtime: 45, episodeNumber: 2))

        let movie = makeItem(id: "movie_61", title: "Day Movie", type: .movie, releaseDate: date(2026, 1, 1), state: "Completed")
        movie.lastStateChangeDate = date(2026, 3, 10)
        movie.cachedRuntime = 120
        context.insert(movie)
        try? context.save()

        let review = await YearInReviewService(modelContainer: container).compute(year: 2026)

        let dayKey = Calendar.current.startOfDay(for: date(2026, 3, 10))
        let titles = review.titlesByDay[dayKey] ?? []
        XCTAssertEqual(titles.count, 2)
        let showEntry = titles.first { $0.type == .tvShow }
        XCTAssertEqual(showEntry?.episodeCount, 2)
        let movieEntry = titles.first { $0.type == .movie }
        XCTAssertEqual(movieEntry?.episodeCount, 0)
    }

    @MainActor
    func testMonthStatsAndMonthTitles() async throws {
        let fixture = try makeContainer()
        let container = fixture.container
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let context = container.mainContext

        let show = makeItem(id: "tv_70", title: "Month Show", type: .tvShow, releaseDate: date(2026, 1, 1), state: "Active")
        show.tasteValue = TasteValue.love.rawValue
        context.insert(show)
        context.insert(makeEpisode(showID: 70, watchedAt: date(2026, 8, 10), runtime: 50, episodeNumber: 1))
        context.insert(makeEpisode(showID: 70, watchedAt: date(2026, 8, 11), runtime: 50, episodeNumber: 2))

        let movie = makeItem(id: "movie_71", title: "Month Movie", type: .movie, releaseDate: date(2026, 2, 1), state: "Completed")
        movie.tasteValue = TasteValue.like.rawValue
        movie.lastStateChangeDate = date(2026, 8, 15)
        movie.cachedRuntime = 100
        context.insert(movie)
        try? context.save()

        let review = await YearInReviewService(modelContainer: container).compute(year: 2026)
        let augStats = review.monthStats(for: date(2026, 8, 1))

        XCTAssertEqual(augStats.movies, 1)
        XCTAssertEqual(augStats.series, 1)
        XCTAssertEqual(augStats.minutes, 200)

        let augTitles = review.monthTitles(for: date(2026, 8, 1))
        XCTAssertEqual(augTitles.count, 2)
        XCTAssertEqual(augTitles.first?.title, "Month Show") // Loved comes before Liked
    }
}
