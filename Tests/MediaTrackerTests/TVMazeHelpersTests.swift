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

    private func makeResults(_ entries: [(id: Int, name: String, premiered: String?, language: String?)]) -> [TVMazeSearchResult] {
        entries.map { TVMazeSearchResult(score: 0, show: TVMazeSearchShow(id: $0.id, name: $0.name, premiered: $0.premiered, language: $0.language)) }
    }

    func testExactMatchWinsOverFuzzyFirstResult() {
        let results = makeResults([
            (35666, "Kerry Katona: Crazy in Love", "2010-01-01", "English"),
            (58858, "Mary Berry - Love to Cook", "2021-01-01", "English"),
            (93925, "Merry Berry Love", "2024-01-01", "English")
        ])
        XCTAssertEqual(Self.testMatch(for: "Merry Berry Love", in: results)?.show.id, 93925)
    }

    func testExactMatchIsCaseAndWhitespaceInsensitive() {
        let results = makeResults([(1, "THE  DEALER", "2023-01-01", "English")])
        XCTAssertEqual(Self.testMatch(for: "the dealer", in: results)?.show.id, 1)

        let ampersand = makeResults([(2, "Juliet & Juliet", "2023-01-01", "English")])
        XCTAssertEqual(Self.testMatch(for: "juliet & juliet", in: ampersand)?.show.id, 2)
    }

    func testNoExactMatchReturnsNil() {
        let results = makeResults([
            (35666, "Kerry Katona: Crazy in Love", "2010-01-01", "English"),
            (58858, "Mary Berry - Love to Cook", "2021-01-01", "English")
        ])
        XCTAssertNil(Self.testMatch(for: "Merry Berry Love", in: results), "No exact match must resolve nil (use TMDB details only)")
    }

    func testNoExactMatchEvenWhenSubstringMatches() {
        let results = makeResults([(1, "Love Me to Hurt Me", "2020-01-01", "English")])
        XCTAssertNil(Self.testMatch(for: "Love Me", in: results))
    }

    func testDisambiguatesByYearAndLanguage() {
        // "My Boss": Chinese 2024 vs Thai upcoming/unreleased
        let results = makeResults([
            (73773, "My Boss", "2024-01-04", "Chinese")
        ])

        // When looking for 2024 Chinese show -> matches 73773
        let chineseMatch = APIClient.bestTVMazeMatch(for: "My Boss", releaseYear: 2024, language: "zh", in: results)
        XCTAssertEqual(chineseMatch?.show.id, 73773)

        // When looking for upcoming Thai show (no release year yet, language "th") -> must reject 73773
        let thaiMatch = APIClient.bestTVMazeMatch(for: "My Boss", releaseYear: nil, language: "th", in: results)
        XCTAssertNil(thaiMatch, "Older Chinese series must not be matched to an unreleased Thai series")

        // When looking for a 2026 show -> must reject 2024 show (+2 years difference)
        let futureMatch = APIClient.bestTVMazeMatch(for: "My Boss", releaseYear: 2026, language: "zh", in: results)
        XCTAssertNil(futureMatch, "A show 2+ years apart must not match")
    }

    private static func testMatch(for title: String, in results: [TVMazeSearchResult]) -> TVMazeSearchResult? {
        APIClient.exactTVMazeMatch(for: title, in: results)
    }
}
