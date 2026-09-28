import XCTest
import SwiftUI
import UserNotifications
@testable import MediaTracker

/// Classification of scheduled notifications by type.
///
/// The season-end, episode and movie buckets are what the notification
/// scheduling work in #58/#59 added, and they are distinguished purely by
/// identifier shape and payload. That is easy to break silently — a misparse
/// would show a season-end alert in the "New Episodes" group, or hide the
/// removal of the day-2 reminder.
@MainActor
final class ScheduledNotificationClassificationTests: MTTestCase {
    private func makeRequest(
        identifier: String,
        title: String = "Some Show",
        subtitle: String? = nil,
        body: String? = nil,
        itemType: String? = "tvShow",
        season: Int? = nil,
        episode: Int? = nil
    ) -> UNNotificationRequest {
        var userInfo: [String: Any] = [:]
        if let itemType { userInfo["ITEM_TYPE"] = itemType }
        if let season { userInfo["SEASON_NUMBER"] = season }
        if let episode { userInfo["EPISODE_NUMBER"] = episode }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle ?? ""
        content.body = body ?? ""
        content.userInfo = userInfo
        let components = DateComponents(year: 2026, month: 10, day: 7, hour: 20, minute: 0)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func groups(_ requests: [UNNotificationRequest]) -> [ScheduledNotificationsView.Group] {
        ScheduledNotificationsView.makeGroups(from: requests)
    }

    private func group(_ requests: [UNNotificationRequest], _ kind: ScheduledNotificationsView.Kind) -> ScheduledNotificationsView.Group? {
        groups(requests).first { $0.kind == kind }
    }

    func testBareTVIdentifierIsClassifiedAsEpisode() {
        let request = makeRequest(identifier: "tv_1400", title: "Ted Lasso", season: 4, episode: 9)
        let result = groups([request])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.kind, .episode)
        XCTAssertEqual(result.first?.items.first?.detail, "S4E9")
    }

    func testSeasonEndIdentifierIsClassifiedSeparately() {
        let request = makeRequest(
            identifier: "tv_1400-seasonend-S4",
            title: "Ted Lasso",
            subtitle: "Season 4 ends today"
        )
        let result = groups([request])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.kind, .seasonEnd)
        // Must not be lumped in with the per-episode alert for the same title.
        XCTAssertEqual(result.first?.items.first?.detail, "Season 4 ends today")
    }

    func testEpisodeAndSeasonEndForSameTitleLandInDifferentGroups() {
        let requests = [
            makeRequest(identifier: "tv_1400", title: "Ted Lasso", season: 4, episode: 9),
            makeRequest(identifier: "tv_1400-seasonend-S4", title: "Ted Lasso", subtitle: "Season 4 ends today")
        ]
        XCTAssertEqual(groups(requests).count, 2)
        XCTAssertEqual(group(requests, .episode)?.items.count, 1)
        XCTAssertEqual(group(requests, .seasonEnd)?.items.count, 1)
    }

    func testMovieIdentifierIsClassifiedAsMovie() {
        let request = makeRequest(identifier: "movie_603", title: "The Matrix", itemType: "movie")
        XCTAssertEqual(groups([request]).first?.kind, .movie)
    }

    func testWeeklyDigestIsClassifiedAsDigest() {
        let request = makeRequest(
            identifier: "weekly-digest",
            title: "Your week",
            subtitle: "Weekly Digest",
            itemType: "weekly_digest"
        )
        XCTAssertEqual(groups([request]).first?.kind, .digest)
    }

    /// The day-2 reminder was removed in #58. If any are still pending they are
    /// leftovers from an older build and should be visibly flagged, not shown
    /// as a normal alert.
    func testLegacyDaySuffixesAreFlaggedSeparately() {
        let requests = [
            makeRequest(identifier: "tv_1400-day1", title: "Ted Lasso", season: 4, episode: 9),
            makeRequest(identifier: "tv_1400-day2", title: "Ted Lasso", body: "In case you missed it")
        ]
        let legacy = group(requests, .legacy)
        XCTAssertEqual(legacy?.items.count, 2)
        XCTAssertNil(group(requests, .episode))
    }

    func testSeasonEndSentWithEpisodeNumberSentinelStaysSeasonEnd() {
        // The season-end payload uses EPISODE_NUMBER -1 to mark itself as
        // season-level; it must not be read as an episode.
        let request = makeRequest(
            identifier: "tv_1400-seasonend-S2",
            title: "Only Murders",
            subtitle: "Season 2 ends today",
            season: 2,
            episode: -1
        )
        XCTAssertEqual(groups([request]).first?.kind, .seasonEnd)
    }

    func testGroupsAreOrderedByPriority() {
        let requests = [
            makeRequest(identifier: "weekly-digest", title: "Week", itemType: "weekly_digest"),
            makeRequest(identifier: "movie_603", title: "The Matrix", itemType: "movie"),
            makeRequest(identifier: "tv_1400", title: "Ted Lasso", season: 4, episode: 9),
            makeRequest(identifier: "tv_1400-seasonend-S4", title: "Ted Lasso", subtitle: "Season 4 ends today")
        ]
        XCTAssertEqual(
            groups(requests).map(\.kind),
            [.seasonEnd, .episode, .movie, .digest]
        )
    }

    func testItemsWithinGroupAreSortedByFireDate() {
        let early = UNNotificationRequest(
            identifier: "tv_1",
            content: Self.content(season: 1, episode: 1),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: 2026, month: 10, day: 1, hour: 20, minute: 0),
                repeats: false
            )
        )
        let late = UNNotificationRequest(
            identifier: "tv_2",
            content: Self.content(season: 1, episode: 2),
            trigger: UNCalendarNotificationTrigger(
                dateMatching: DateComponents(year: 2026, month: 10, day: 20, hour: 20, minute: 0),
                repeats: false
            )
        )
        let items = groups([late, early]).first?.items ?? []
        XCTAssertEqual(items.map(\.id), ["tv_1", "tv_2"])
    }

    func testEmptyInputProducesNoGroups() {
        XCTAssertTrue(groups([]).isEmpty)
    }

    func testNonCalendarTriggerDoesNotCrash() {
        // A request with no trigger, or an interval trigger, should still list.
        let content = Self.content(season: 1, episode: 1)
        let request = UNNotificationRequest(
            identifier: "tv_1",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        )
        let result = groups([request])
        XCTAssertEqual(result.first?.kind, .episode)
    }

    private static func content(season: Int, episode: Int) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Show"
        content.userInfo = [
            "ITEM_TYPE": "tvShow",
            "SEASON_NUMBER": season,
            "EPISODE_NUMBER": episode
        ]
        return content
    }
}
