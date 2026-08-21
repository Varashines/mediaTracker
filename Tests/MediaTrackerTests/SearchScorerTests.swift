import XCTest
@testable import MediaTracker

final class SearchScorerTests: XCTestCase {
    private func payload(
        title: String = "",
        overview: String = "",
        creators: [String] = [],
        cast: [String] = [],
        genres: [String] = [],
        providers: [String] = [],
        network: String? = nil,
        language: String? = nil
    ) -> SearchPayload {
        SearchPayload(
            title: title.lowercased(),
            overview: overview.lowercased(),
            creators: creators.map { $0.lowercased() },
            cast: cast.map { $0.lowercased() },
            genres: genres.map { $0.lowercased() },
            providers: providers.map { $0.lowercased() },
            network: network?.lowercased(),
            language: language?.lowercased()
        )
    }

    func testExactGenreSearchIsEligible() {
        let evaluation = SearchScorer(tokens: ["ACTION"]).evaluate(
            payload: payload(genres: ["Action"])
        )

        XCTAssertEqual(evaluation.score, 120)
        XCTAssertTrue(evaluation.isEligibleForAllTokens)
    }

    func testExactProviderSearchIsEligible() {
        let evaluation = SearchScorer(tokens: ["Netflix"]).evaluate(
            payload: payload(providers: ["Netflix"])
        )

        XCTAssertEqual(evaluation.score, 120)
        XCTAssertTrue(evaluation.isEligibleForAllTokens)
    }

    func testOverviewOnlySearchIsNotEligible() {
        let evaluation = SearchScorer(tokens: ["noir"]).evaluate(
            payload: payload(overview: "A dark noir mystery")
        )

        XCTAssertEqual(evaluation.score, 10)
        XCTAssertTrue(evaluation.matchesAll)
        XCTAssertFalse(evaluation.isEligibleForAllTokens)
    }

    func testTitleRanksAboveGenreMatch() {
        let scorer = SearchScorer(tokens: ["action"])
        let titleScore = scorer.score(item: TestSearchItem(searchPayload: payload(title: "Action Hero")))
        let genreScore = scorer.score(item: TestSearchItem(searchPayload: payload(genres: ["Action"])))

        XCTAssertGreaterThan(titleScore, genreScore)
    }

    func testMultipleDirectFacetTokensAreEligible() {
        let evaluation = SearchScorer(tokens: ["action", "netflix"]).evaluate(
            payload: payload(genres: ["Action"], providers: ["Netflix"])
        )

        XCTAssertTrue(evaluation.matchesAll)
        XCTAssertTrue(evaluation.isEligibleForAllTokens)
        XCTAssertEqual(evaluation.score, 240)
    }

    func testTokenizationNormalizesCaseAndDuplicates() {
        XCTAssertEqual(
            SearchScorer.tokenize("  ACTION  action  Netflix "),
            ["action", "netflix"]
        )
    }
}

private struct TestSearchItem: SearchScorable {
    let searchPayload: SearchPayload
    var searchableText: String { "" }
}
