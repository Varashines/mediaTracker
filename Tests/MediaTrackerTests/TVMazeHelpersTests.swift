import XCTest
@testable import MediaTracker

/// Regression tests for the shared TVMaze helpers (`strippedSummary`,
/// `rawBySeason`) that replaced four copies of inline HTML-stripping and two
/// copies of season-grouping closures.
final class TVMazeHelpersTests: XCTestCase {

    private func makeEpisode(
        season: Int?, number: Int?, name: String?,
        airdate: String = "", summary: String? = nil, runtime: Int? = nil
    ) -> TVMazeEpisode {
        TVMazeEpisode(
            season: season, number: number, name: name,
            airdate: airdate, airtime: "", airstamp: nil,
            summary: summary, runtime: runtime
        )
    }

    // MARK: - strippedSummary

    func testStrippedSummaryRemovesTagsAndTrims() {
        let episode = makeEpisode(
            season: 1, number: 1, name: "Pilot", airdate: "2024-01-01",
            summary: "<p>Hello <b>World</b></p>\n"
        )
        XCTAssertEqual(episode.strippedSummary, "Hello World")
    }

    func testStrippedSummaryHandlesNestedTags() {
        let episode = makeEpisode(
            season: 1, number: 2, name: "Two", airdate: "2024-01-02",
            summary: "  <div><a href=\"x\">Link</a> and <i>italic</i></div>  "
        )
        XCTAssertEqual(episode.strippedSummary, "Link and italic")
    }

    func testStrippedSummaryReturnsNilForNilSummary() {
        let episode = makeEpisode(season: 1, number: 3, name: "Three", airdate: "2024-01-03")
        XCTAssertNil(episode.strippedSummary)
    }

    // MARK: - rawBySeason

    func testRawBySeasonGroupsBySeasonSortedByNumber() {
        let episodes = [
            makeEpisode(season: 2, number: 2, name: "S2E2"),
            makeEpisode(season: 1, number: 3, name: "S1E3"),
            makeEpisode(season: 1, number: 1, name: "S1E1"),
            makeEpisode(season: 1, number: 2, name: "S1E2"),
            makeEpisode(season: 0, number: 5, name: "Special")
        ]

        let grouped = TVMazeEpisode.rawBySeason(episodes)

        XCTAssertEqual(Set(grouped.keys), [1, 2], "Season 0 (specials) must be excluded")
        XCTAssertEqual(grouped[1]?.map(\.name), ["S1E1", "S1E2", "S1E3"], "Episodes sorted by number within season")
        XCTAssertEqual(grouped[2]?.map(\.name), ["S2E2"])
    }

    func testRawBySeasonHandlesEmptyInput() {
        XCTAssertTrue(TVMazeEpisode.rawBySeason([]).isEmpty)
    }
}
