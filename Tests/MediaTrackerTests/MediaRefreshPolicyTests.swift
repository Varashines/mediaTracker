import XCTest
@testable import MediaTracker

final class MediaRefreshPolicyTests: XCTestCase {
    private let now = Date()

    func testEvolvingStatusUsesWeeklyRefresh() {
        let lastUpdated = now.addingTimeInterval(-(8 * 86400))

        XCTAssertTrue(MediaRefreshPolicy.shouldRefresh(
            status: "Returning Series",
            type: .tvShow,
            lastUpdated: lastUpdated,
            now: now
        ))
        XCTAssertFalse(MediaRefreshPolicy.shouldRefresh(
            status: "In Production",
            type: .movie,
            lastUpdated: now.addingTimeInterval(-(6 * 86400)),
            now: now
        ))
    }

    func testTerminatedStatusesAreSkipped() {
        XCTAssertFalse(MediaRefreshPolicy.shouldRefresh(
            status: "Ended",
            type: .tvShow,
            lastUpdated: now.addingTimeInterval(-(365 * 86400)),
            now: now
        ))
        XCTAssertFalse(MediaRefreshPolicy.shouldRefresh(
            status: "Canceled",
            type: .movie,
            lastUpdated: now.addingTimeInterval(-(365 * 86400)),
            now: now
        ))
    }

    func testReleasedMoviesUseMonthlyRefresh() {
        XCTAssertTrue(MediaRefreshPolicy.shouldRefresh(
            status: "Released",
            type: .movie,
            lastUpdated: now.addingTimeInterval(-(31 * 86400)),
            now: now
        ))
        XCTAssertFalse(MediaRefreshPolicy.shouldRefresh(
            status: "Released",
            type: .movie,
            lastUpdated: now.addingTimeInterval(-(29 * 86400)),
            now: now
        ))
    }

    func testUnknownAndMissingDataAreRefreshed() {
        XCTAssertTrue(MediaRefreshPolicy.shouldRefresh(status: nil, type: .movie, lastUpdated: nil, now: now))
        XCTAssertTrue(MediaRefreshPolicy.shouldRefresh(
            status: "Unknown",
            type: .tvShow,
            lastUpdated: now.addingTimeInterval(-(31 * 86400)),
            now: now
        ))
    }
}
