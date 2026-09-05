import XCTest
@testable import MediaTracker

/// Regression tests for the shared TVMaze helpers (`strippedSummary`,
/// `rawBySeason`) that replaced four copies of inline HTML-stripping and two
/// copies of season-grouping closures.
final class TVMazeHelpersTests: MTTestCase {

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

    // MARK: - exactTVMazeMatch (Merry Berry Love regression: fuzzy search
    // ranked "Kerry Katona: Crazy in Love" first and the app blindly took it)

    private func makeResults(_ entries: [(id: Int, name: String)]) -> [TVMazeSearchResult] {
        entries.map { TVMazeSearchResult(score: 0, show: TVMazeSearchShow(id: $0.id, name: $0.name)) }
    }

    func testExactMatchWinsOverFuzzyFirstResult() {
        let results = makeResults([
            (35666, "Kerry Katona: Crazy in Love"),
            (58858, "Mary Berry - Love to Cook"),
            (93925, "Merry Berry Love")
        ])
        XCTAssertEqual(Self.testMatch(for: "Merry Berry Love", in: results)?.show.id, 93925)
    }

    func testExactMatchIsCaseAndWhitespaceInsensitive() {
        let results = makeResults([(1, "THE  DEALER")])
        XCTAssertEqual(Self.testMatch(for: "the dealer", in: results)?.show.id, 1)

        let ampersand = makeResults([(2, "Juliet & Juliet")])
        XCTAssertEqual(Self.testMatch(for: "juliet & juliet", in: ampersand)?.show.id, 2)
    }

    func testNoExactMatchReturnsNil() {
        let results = makeResults([
            (35666, "Kerry Katona: Crazy in Love"),
            (58858, "Mary Berry - Love to Cook")
        ])
        XCTAssertNil(Self.testMatch(for: "Merry Berry Love", in: results), "No exact match must resolve nil (use TMDB details only)")
    }

    func testNoExactMatchEvenWhenSubstringMatches() {
        let results = makeResults([(1, "Love Me to Hurt Me")])
        XCTAssertNil(Self.testMatch(for: "Love Me", in: results))
    }

    private static func testMatch(for title: String, in results: [TVMazeSearchResult]) -> TVMazeSearchResult? {
        APIClient.exactTVMazeMatch(for: title, in: results)
    }
}
