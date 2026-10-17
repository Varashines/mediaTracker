import XCTest
@testable import MediaTracker

/// The rule that decides whether a pulled watch is already in the ledger.
///
/// It failed twice on the same viewing: the two apps write episode ids in different spellings
/// (`293610_1_3` here, `tv_293610_s1_e3` from Android), and Android stamped its copy from local
/// wall-clock time labelled UTC — hours ahead, occasionally past midnight. So one watch became two
/// events, and because Year in Review groups by local day, the same episode appeared on two days.
final class LedgerDedupTests: XCTestCase {

    private let iso = ISO8601DateFormatter()

    private func date(_ string: String) -> Date {
        iso.date(from: string) ?? .distantPast
    }

    // MARK: - Episode identifier

    func testCanonicalisesTheLegacySpelling() {
        XCTAssertEqual(EpisodeIdentifier.canonical("293610_1_3"), "tv_293610_s1_e3")
        XCTAssertEqual(EpisodeIdentifier.canonical("1399_2_10"), "tv_1399_s2_e10")
    }

    func testLeavesTheCanonicalSpellingAlone() {
        XCTAssertEqual(EpisodeIdentifier.canonical("tv_293610_s1_e3"), "tv_293610_s1_e3")
    }

    func testBothSpellingsCollapseToTheSameValue() {
        XCTAssertEqual(
            EpisodeIdentifier.canonical("293610_1_3"),
            EpisodeIdentifier.canonical("tv_293610_s1_e3")
        )
    }

    func testMoviesCarryNoEpisodeIdentifier() {
        XCTAssertNil(EpisodeIdentifier.canonical(nil))
        XCTAssertNil(EpisodeIdentifier.canonical(""))
    }

    func testUnrecognisedValuesPassThroughUntouched() {
        XCTAssertEqual(EpisodeIdentifier.canonical("movie_550"), "movie_550")
        XCTAssertEqual(EpisodeIdentifier.canonical("not-an-id"), "not-an-id")
    }

    // MARK: - Same watch

    func testIdenticalInstantsAreTheSameWatch() {
        XCTAssertTrue(SyncTimestamps.isSameWatch(date("2026-10-16T16:10:16Z"), date("2026-10-16T16:10:16Z")))
    }

    func testAnOffsetShiftIsTheSameWatch() {
        // The Doctor X pair: the correct stamp, and the +5:30 one from the old Android formatter.
        XCTAssertTrue(SyncTimestamps.isSameWatch(date("2026-10-16T16:10:16Z"), date("2026-10-16T21:40:16Z")))
    }

    func testAShiftThatCrossesMidnightIsStillTheSameWatch() {
        let correct = date("2026-10-16T23:50:00Z")
        let mislabelled = date("2026-10-17T05:20:00Z")   // same instant family, +5:30
        XCTAssertTrue(SyncTimestamps.isSameWatch(correct, mislabelled))
    }

    func testARewatchTheNextDayIsADifferentWatch() {
        XCTAssertFalse(SyncTimestamps.isSameWatch(date("2026-10-16T16:10:16Z"), date("2026-10-17T16:10:16Z")))
    }

    // MARK: - The case that started this

    /// One viewing, recorded here under the legacy id and pulled back under the canonical one,
    /// stamped 5½ hours later by the old Android formatter.
    func testTheDoctorXPairCountsAsOneWatch() {
        let storedLocally = (episodeID: "293610_1_3", watchedAt: date("2026-10-16T16:10:16Z"))
        let pulledFromCloud = (episodeID: "tv_293610_s1_e3", watchedAt: date("2026-10-16T21:40:16Z"))

        XCTAssertEqual(
            EpisodeIdentifier.canonical(storedLocally.episodeID),
            EpisodeIdentifier.canonical(pulledFromCloud.episodeID),
            "the two spellings describe the same episode"
        )
        XCTAssertTrue(
            SyncTimestamps.isSameWatch(storedLocally.watchedAt, pulledFromCloud.watchedAt),
            "and the shifted stamp describes the same viewing"
        )
    }
}
