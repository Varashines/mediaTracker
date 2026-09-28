import XCTest
import SwiftData
import UserNotifications
@testable import MediaTracker

/// Coverage for the stale-notification reconcile, which decides what to delete
/// from the system queue on every scheduling pass.
///
/// The bug this exists for: a season-end alert is scheduled as
/// `tv-tv_97546-seasonend-S4`. The reconcile derived the item id by stripping the
/// `tv-` prefix only, producing `tv_97546-seasonend-S4`, which never matches an
/// upcoming item id — so every season-end alert was scheduled correctly and then
/// deleted as stale on the very next pass. Nothing in the UI ever showed one, and
/// the app looked like it was scheduling almost nothing.
@MainActor
final class NotificationReconcileTests: MTTestCase {
    private func request(_ identifier: String) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: UNMutableNotificationContent(),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: 2026, month: 10, day: 7, hour: 20, minute: 0),
                repeats: false
            )
        )
    }

    private func stale(
        _ identifiers: [String],
        upcoming: Set<String>
    ) -> [String] {
        NotificationManager.staleIdentifiers(
            from: identifiers.map(request),
            upcomingIDs: upcoming
        )
    }

    // MARK: - itemID extraction

    func testItemIDFromBareTVIdentifier() {
        XCTAssertEqual(NotificationManager.itemID(fromIdentifier: "tv-tv_97546"), "tv_97546")
    }

    func testItemIDFromMovieIdentifier() {
        XCTAssertEqual(NotificationManager.itemID(fromIdentifier: "movie-movie_603"), "movie_603")
    }

    /// The regression: the season-end suffix must be stripped.
    func testItemIDFromSeasonEndIdentifier() {
        XCTAssertEqual(
            NotificationManager.itemID(fromIdentifier: "tv-tv_97546-seasonend-S4"),
            "tv_97546"
        )
    }

    func testItemIDFromDay1Identifier() {
        XCTAssertEqual(NotificationManager.itemID(fromIdentifier: "tv-tv_97546-day1"), "tv_97546")
    }

    func testItemIDIsNilForWeeklyDigest() {
        XCTAssertNil(NotificationManager.itemID(fromIdentifier: "weekly-digest"))
    }

    // MARK: - reconcile

    /// The exact failure: a valid season-end alert for an upcoming show must
    /// survive a reconcile pass.
    func testSeasonEndAlertForUpcomingShowIsKept() {
        let result = stale(["tv-tv_97546-seasonend-S4"], upcoming: ["tv_97546"])
        XCTAssertTrue(result.isEmpty, "season-end alert must not be deleted as stale")
    }

    func testSeasonEndAlertForEndedShowIsRemoved() {
        let result = stale(["tv-tv_97546-seasonend-S4"], upcoming: [])
        XCTAssertEqual(result, ["tv-tv_97546-seasonend-S4"])
    }

    func testBareEpisodeAlertForUpcomingShowIsKept() {
        XCTAssertTrue(stale(["tv-tv_97546"], upcoming: ["tv_97546"]).isEmpty)
    }

    func testBareEpisodeAlertForNoLongerUpcomingIsRemoved() {
        XCTAssertEqual(stale(["tv-tv_97546"], upcoming: []), ["tv-tv_97546"])
    }

    func testMovieAlertForUpcomingMovieIsKept() {
        XCTAssertTrue(stale(["movie-movie_1327821"], upcoming: ["movie_1327821"]).isEmpty)
    }

    /// Day-2 requests are no longer produced, so any left over are removed
    /// unconditionally.
    func testDay2RequestIsAlwaysStaleEvenForUpcomingItem() {
        XCTAssertEqual(stale(["tv-tv_97546-day2"], upcoming: ["tv_97546"]), ["tv-tv_97546-day2"])
    }

    func testDay1RequestSurvivesForUpcomingItem() {
        XCTAssertTrue(stale(["tv-tv_97546-day1"], upcoming: ["tv_97546"]).isEmpty)
    }

    /// The digest has no item id, so it must never be treated as stale.
    func testWeeklyDigestIsNeverStale() {
        XCTAssertTrue(stale(["weekly-digest"], upcoming: []).isEmpty)
    }

    /// A mixed queue resembling a real library: the item-scoped, still-upcoming
    /// requests survive and only genuinely dead ones go.
    func testMixedQueueKeepsLiveAlertsAndDropsDeadOnes() {
        let upcoming: Set<String> = ["tv_97546", "movie_1327821", "tv_258165"]
        let queue = [
            "tv-tv_97546",                 // live episode alert
            "tv-tv_97546-seasonend-S4",    // live season-end alert
            "tv-tv_258165-seasonend-S1",   // live season-end alert
            "movie-movie_1327821",         // live movie alert
            "weekly-digest",               // not item-scoped
            "tv-tv_999999",                // show no longer upcoming
            "movie-movie_555555",          // movie no longer upcoming
            "tv-tv_97546-day2"             // obsolete reminder
        ]
        let result = Set(stale(queue, upcoming: upcoming))
        XCTAssertEqual(result, ["tv-tv_999999", "movie-movie_555555", "tv-tv_97546-day2"])
    }
}
