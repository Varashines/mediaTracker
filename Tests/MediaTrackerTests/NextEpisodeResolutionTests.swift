import XCTest
import SwiftData
@testable import MediaTracker

/// Covers the episode/season resolution that drives notifications.
///
/// These exist because the notification path used to read a cached
/// `nextEpisodeNumber` from TMDB/TVMaze — a snapshot of what the *network* airs
/// next, never revised when an episode is marked watched. It named episodes
/// already seen in 13 of 32 upcoming shows on a real library.
final class NextEpisodeResolutionTests: MTTestCase {
    /// Containers must outlive the test method. A `ModelContext` keeps working
    /// after its `ModelContainer` is released, so a locally-scoped container
    /// traps inside SwiftData on the next model access — the same hazard the
    /// `MediaItem` setters guard against.
    private var retainedContainers: [ModelContainer] = []

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            TVEpisode.self, WatchCycle.self, WatchEvent.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        retainedContainers.append(container)
        return container
    }

    /// Builds a show with one season of `episodeCount` episodes, all unwatched,
    /// airing `firstAir + n days`.
    @MainActor
    private func makeShow(
        tmdbID: Int,
        seasonNumber: Int = 1,
        episodeCount: Int,
        firstAir: Date,
        watchedNumbers: Set<Int> = []
    ) throws -> TVShowDetails {
        let context = try makeContainer().mainContext
        let show = MediaItem(id: "tv_\(tmdbID)", title: "Show \(tmdbID)", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: tmdbID)
        let season = TVSeason(seasonNumber: seasonNumber, name: "S\(seasonNumber)", episodeCount: episodeCount, showID: tmdbID)
        for n in 1...episodeCount {
            let episode = TVEpisode(
                episodeNumber: n,
                seasonNumber: seasonNumber,
                name: "E\(n)",
                overview: "",
                isWatched: watchedNumbers.contains(n),
                showID: tmdbID
            )
            episode.airDateValue = firstAir.addingTimeInterval(TimeInterval(n - 1) * .days1)
            season.episodes.append(episode)
        }
        details.seasons.append(season)
        show.tvShowDetails = details
        context.insert(show)
        return details
    }

    // MARK: - nextUnwatchedUnairedEpisode

    @MainActor
    func testPicksEarliestAiredUnwatchedUnairedEpisode() throws {
        let now = Date()
        let details = try makeShow(
            tmdbID: 1,
            episodeCount: 5,
            firstAir: now.addingTimeInterval(2 * .days1),
            watchedNumbers: [1, 2]
        )
        let resolved = details.nextUnwatchedUnairedEpisode(now: now)
        XCTAssertEqual(resolved?.episodeNumber, 3)
    }

    @MainActor
    func testSkipsAlreadyAiredEpisodes() throws {
        // Everything unwatched has already aired, so there is nothing to announce.
        let now = Date()
        let details = try makeShow(tmdbID: 2, episodeCount: 3, firstAir: now.addingTimeInterval(-5 * .days1))
        XCTAssertNil(details.nextUnwatchedUnairedEpisode(now: now))
    }

    @MainActor
    func testIgnoresSpecials() throws {
        // A season 0 episode airing sooner must not win over the season 1 episode.
        let now = Date()
        let details = try makeShow(tmdbID: 3, episodeCount: 3, firstAir: now.addingTimeInterval(5 * .days1))
        let special = TVEpisode(episodeNumber: 1, seasonNumber: 0, name: "Special", overview: "", showID: 3)
        special.airDateValue = now.addingTimeInterval(.days1)
        let specialSeason = TVSeason(seasonNumber: 0, name: "Specials", episodeCount: 1, showID: 3)
        specialSeason.episodes.append(special)
        details.seasons.append(specialSeason)

        XCTAssertEqual(details.nextUnwatchedUnairedEpisode(now: now)?.episodeNumber, 1)
        XCTAssertEqual(details.nextUnwatchedUnairedEpisode(now: now)?.seasonNumber, 1)
    }

    @MainActor
    func testPicksSoonerAiredEpisodeRatherThanLowestNumber() throws {
        // Regression shape for the original bug: cached data named episode 1
        // after 1 and 2 were already watched.
        let now = Date()
        let details = try makeShow(
            tmdbID: 4,
            episodeCount: 6,
            firstAir: now.addingTimeInterval(3 * .days1),
            watchedNumbers: [1, 2, 3, 4]
        )
        XCTAssertEqual(details.nextUnwatchedUnairedEpisode(now: now)?.episodeNumber, 5)
    }

    // MARK: - nextUnwatchedEpisode

    @MainActor
    func testNextUnwatchedEpisodeUsesSeasonThenEpisodeOrder() throws {
        let now = Date()
        let details = try makeShow(
            tmdbID: 5,
            episodeCount: 4,
            firstAir: now.addingTimeInterval(-10 * .days1),
            watchedNumbers: [1, 2]
        )
        let resolved = details.nextUnwatchedEpisode()
        XCTAssertEqual(resolved?.episodeNumber, 3)
    }

    @MainActor
    func testNextUnwatchedEpisodeSkipsSpecials() throws {
        let now = Date()
        let details = try makeShow(tmdbID: 6, episodeCount: 2, firstAir: now.addingTimeInterval(-3 * .days1))
        let special = TVEpisode(episodeNumber: 1, seasonNumber: 0, name: "Special", overview: "", showID: 6)
        let specialSeason = TVSeason(seasonNumber: 0, name: "Specials", episodeCount: 1, showID: 6)
        specialSeason.episodes.append(special)
        details.seasons.append(specialSeason)

        XCTAssertEqual(details.nextUnwatchedEpisode()?.seasonNumber, 1)
    }

    @MainActor
    func testNextUnwatchedEpisodeReturnsNilWhenAllWatched() throws {
        let now = Date()
        let details = try makeShow(
            tmdbID: 7,
            episodeCount: 3,
            firstAir: now.addingTimeInterval(-9 * .days1),
            watchedNumbers: [1, 2, 3]
        )
        XCTAssertNil(details.nextUnwatchedEpisode())
    }

    // MARK: - upcomingSeasonFinale

    @MainActor
    func testFindsFinaleOfFullySyncedSeason() throws {
        let now = Date()
        let details = try makeShow(
            tmdbID: 8,
            episodeCount: 8,
            firstAir: now.addingTimeInterval(2 * .days1)
        )
        let finale = details.upcomingSeasonFinale(within: .days14, now: now)
        XCTAssertEqual(finale?.season.seasonNumber, 1)
        XCTAssertEqual(finale?.episode.episodeNumber, 8)
    }

    @MainActor
    func testIgnoresUnsyncedSeasonWhoseOnlyEpisodeIsThePremiere() throws {
        // The load-bearing guard. A season not yet fully fetched reports
        // episodeCount 1, so "highest episode number" is the premiere. Treating
        // that as a finale produced alerts for Abbott Elementary S6E1,
        // 9-1-1 S10E1, Silo S4E1 — 11 of 45 candidates on a real library.
        let now = Date()
        let unsynced = try makeShow(
            tmdbID: 9,
            episodeCount: 1,
            firstAir: now.addingTimeInterval(2 * .days1)
        )
        XCTAssertNil(unsynced.upcomingSeasonFinale(within: .days14, now: now))

        let twoEpisodes = try makeShow(
            tmdbID: 10,
            episodeCount: 2,
            firstAir: now.addingTimeInterval(2 * .days1)
        )
        XCTAssertNil(twoEpisodes.upcomingSeasonFinale(within: .days14, now: now))
    }

    @MainActor
    func testSkipsFinaleAlreadyWatched() throws {
        let now = Date()
        let details = try makeShow(
            tmdbID: 11,
            episodeCount: 6,
            firstAir: now.addingTimeInterval(2 * .days1),
            watchedNumbers: [6]
        )
        XCTAssertNil(details.upcomingSeasonFinale(within: .days14, now: now))
    }

    @MainActor
    func testSkipsFinaleOutsideWindow() throws {
        let now = Date()
        let details = try makeShow(
            tmdbID: 12,
            episodeCount: 5,
            firstAir: now.addingTimeInterval(30 * .days1)
        )
        XCTAssertNil(details.upcomingSeasonFinale(within: .days14, now: now))
    }

    @MainActor
    func testSkipsFinaleInThePast() throws {
        let now = Date()
        let details = try makeShow(
            tmdbID: 13,
            episodeCount: 5,
            firstAir: now.addingTimeInterval(-20 * .days1)
        )
        XCTAssertNil(details.upcomingSeasonFinale(within: .days14, now: now))
    }

    @MainActor
    func testIgnoresSpecialsAsAFinale() throws {
        let now = Date()
        let details = try makeShow(tmdbID: 14, episodeCount: 4, firstAir: now.addingTimeInterval(3 * .days1))
        let special = TVEpisode(episodeNumber: 9, seasonNumber: 0, name: "Special", overview: "", showID: 14)
        special.airDateValue = now.addingTimeInterval(.days1)
        let specialSeason = TVSeason(seasonNumber: 0, name: "Specials", episodeCount: 9, showID: 14)
        specialSeason.episodes.append(special)
        details.seasons.append(specialSeason)

        let finale = details.upcomingSeasonFinale(within: .days14, now: now)
        XCTAssertEqual(finale?.season.seasonNumber, 1)
    }

    @MainActor
    func testReturnsSoonestFinaleWhenTwoSeasonsQualify() throws {
        let now = Date()
        // Must be inserted into a context: `liveModels` resolves through the
        // model context, so a detached graph reads as empty.
        let context = try makeContainer().mainContext
        let show = MediaItem(id: "tv_15", title: "Show 15", overview: "", type: .tvShow)
        let details = TVShowDetails(tmdbID: 15)

        // Season 1's finale is further out than season 2's.
        let season1 = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 4, showID: 15)
        for n in 1...4 {
            let episode = TVEpisode(episodeNumber: n, seasonNumber: 1, name: "E\(n)", overview: "", showID: 15)
            episode.airDateValue = now.addingTimeInterval(10 * .days1)
            season1.episodes.append(episode)
        }
        let season2 = TVSeason(seasonNumber: 2, name: "S2", episodeCount: 3, showID: 15)
        for n in 1...3 {
            let episode = TVEpisode(episodeNumber: n, seasonNumber: 2, name: "E\(n)", overview: "", showID: 15)
            episode.airDateValue = now.addingTimeInterval(2 * .days1)
            season2.episodes.append(episode)
        }
        details.seasons.append(season1)
        details.seasons.append(season2)
        show.tvShowDetails = details
        context.insert(show)

        let finale = details.upcomingSeasonFinale(within: .days14, now: now)
        XCTAssertEqual(finale?.season.seasonNumber, 2)
    }
}
