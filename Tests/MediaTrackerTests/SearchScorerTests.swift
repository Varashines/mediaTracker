import XCTest
@testable import MediaTracker

final class SearchScorerTests: MTTestCase {
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

    /// The trigram branch now compares precomputed sets instead of rebuilding
    /// both sides per item. "interstelar" is not a substring of "interstellar",
    /// so this score can only come from that branch.
    func testFuzzyTrigramTitleMatchStillScores() {
        let evaluation = SearchScorer(tokens: ["interstelar"]).evaluate(
            payload: payload(title: "Interstellar")
        )

        XCTAssertEqual(evaluation.score, 50)
        XCTAssertTrue(evaluation.isEligibleForAllTokens)
    }

    /// ASCII fast paths must not break diacritic-insensitive matching. This is a
    /// partial (contains) match, not an exact one — `localizedStandardCompare`
    /// is case-insensitive but does not fold diacritics, so 70 is the pre-existing
    /// score. The test pins that the non-ASCII fallback path still matches at all.
    func testDiacriticInsensitiveGenreMatchStillScores() {
        let evaluation = SearchScorer(tokens: ["drama"]).evaluate(
            payload: payload(genres: ["Dráma"])
        )

        XCTAssertEqual(evaluation.score, 70)
        XCTAssertTrue(evaluation.isEligibleForAllTokens)
    }

    /// Every token is scored once and reused by the AND/OR fallback, so the
    /// fallback must still rank multiple partial matches.
    func testMultiTokenFallbackUsesSameScores() {
        let scorer = SearchScorer(tokens: ["action", "zzzz"])
        let evaluation = scorer.evaluate(payload: payload(genres: ["Action"]))

        XCTAssertFalse(evaluation.isEligibleForAllTokens)
        XCTAssertTrue(evaluation.isEligibleForAnyToken)
        XCTAssertEqual(evaluation.score, 120)
    }
}

private struct TestSearchItem: SearchScorable {
    let searchPayload: SearchPayload
    var searchableText: String { "" }
}
