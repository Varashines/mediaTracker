import XCTest
@testable import MediaTracker

final class RuntimeFallbackTests: XCTestCase {
    private func mazeEpisode(
        season: Int? = 1,
        number: Int?,
        runtime: Int?,
        name: String = "Maze"
    ) -> TVMazeEpisode {
        TVMazeEpisode(
            season: season,
            number: number,
            name: name,
            airdate: "2026-01-01",
            airtime: "",
            airstamp: nil,
            summary: nil,
            runtime: runtime
        )
    }

    func testTMDBRuntimeWinsWhenBothSourcesProvideRuntime() {
        let tmdb = [TVEpisodeResult(
            episodeNumber: 1, name: "TMDB", overview: nil,
            airDate: "2026-01-01", runtime: 50
        )]

        let result = RuntimeFallback.reconcile(
            tmdbEpisodes: tmdb,
            tvmazeSeason: [mazeEpisode(number: 1, runtime: 42)]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].runtime, 50)
        XCTAssertEqual(result[0].name, "TMDB")
    }

    func testTVMazeFillsMissingTMDBRuntime() {
        let tmdb = [TVEpisodeResult(
            episodeNumber: 1, name: "TMDB", overview: nil,
            airDate: "2026-01-01", runtime: nil
        )]

        let result = RuntimeFallback.reconcile(
            tmdbEpisodes: tmdb,
            tvmazeSeason: [mazeEpisode(number: 1, runtime: 42)]
        )

        XCTAssertEqual(result[0].runtime, 42)
        XCTAssertEqual(result[0].name, "TMDB")
    }

    func testValidTVMazeExtraEpisodeIsAppended() {
        let tmdb = [TVEpisodeResult(
            episodeNumber: 1, name: "One", overview: nil,
            airDate: nil, runtime: 50
        )]

        let result = RuntimeFallback.reconcile(
            tmdbEpisodes: tmdb,
            tvmazeSeason: [
                mazeEpisode(number: 1, runtime: 42),
                mazeEpisode(number: 2, runtime: 43, name: "Two")
            ]
        )

        XCTAssertEqual(result.map(\.episodeNumber), [1, 2])
        XCTAssertEqual(result[1].name, "Two")
        XCTAssertEqual(result[1].runtime, 43)
    }

    func testInvalidAndSpecialTVMazeEpisodesAreIgnored() {
        let result = RuntimeFallback.reconcile(
            tmdbEpisodes: [],
            tvmazeSeason: [
                mazeEpisode(season: 0, number: 1, runtime: 10),
                mazeEpisode(number: nil, runtime: 20),
                mazeEpisode(number: 0, runtime: 30)
            ]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testCountMismatchDoesNotReplaceExistingTMDBRuntimes() {
        let tmdb = [
            TVEpisodeResult(episodeNumber: 1, name: "One", overview: nil, airDate: nil, runtime: 50),
            TVEpisodeResult(episodeNumber: 2, name: "Two", overview: nil, airDate: nil, runtime: 51)
        ]

        let result = RuntimeFallback.reconcile(
            tmdbEpisodes: tmdb,
            tvmazeSeason: [mazeEpisode(number: 1, runtime: 40)]
        )

        XCTAssertEqual(result.map(\.runtime), [50, 51])
    }
}
