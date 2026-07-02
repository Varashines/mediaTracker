import XCTest
@testable import MediaTracker

final class DateUtilsTests: XCTestCase {
    func testParseDate() {
        let date = DateUtils.parseDate("2026-04-20")
        XCTAssertNotNil(date)

        let nilDate = DateUtils.parseDate(nil)
        XCTAssertNil(nilDate)

        let badDate = DateUtils.parseDate("not-a-date")
        XCTAssertNil(badDate)
    }

    func testParseEpisodeDateAppleTV() {
        let date = DateUtils.parseEpisodeDate("2026-04-20", serviceName: "Apple TV+")
        XCTAssertNotNil(date)

        let tzET = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tzET
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }

    func testParseEpisodeDateDisneyPlus() {
        let date = DateUtils.parseEpisodeDate("2026-04-20", serviceName: "Disney+")
        XCTAssertNotNil(date)

        let tzET = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tzET
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 3)
        XCTAssertEqual(comps.minute, 0)
    }

    func testParseEpisodeDateNetflix() {
        let date = DateUtils.parseEpisodeDate("2026-04-20", serviceName: "Netflix")
        XCTAssertNotNil(date)

        let tzPT = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tzPT
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 0)
        XCTAssertEqual(comps.minute, 0)
    }

    func testParseEpisodeDateAirstamp() {
        let isoDate = "2026-04-20T20:00:00Z"
        let date = DateUtils.parseEpisodeDate("2026-04-20", airstamp: isoDate)
        XCTAssertNotNil(date)

        var calUtc = Calendar(identifier: .gregorian)
        calUtc.timeZone = TimeZone(identifier: "UTC")!
        let comps = calUtc.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 20)
        XCTAssertEqual(comps.minute, 0)
    }

    func testParseEpisodeDateFallback() {
        let date = DateUtils.parseEpisodeDate("2026-04-20")
        XCTAssertNotNil(date)

        let tzET = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tzET
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 20)
        XCTAssertEqual(comps.minute, 0)
    }

    func testParseEpisodeDateWithTimezone() {
        let date = DateUtils.parseEpisodeDate("2026-04-20", time: "19:00", timezone: "America/Chicago")
        XCTAssertNotNil(date)

        let tzCT = TimeZone(identifier: "America/Chicago")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tzCT
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 4)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 19)
        XCTAssertEqual(comps.minute, 0)
    }

    func testParseEpisodeDateNil() {
        XCTAssertNil(DateUtils.parseEpisodeDate(nil))
    }

    func testFormatRuntime() {
        XCTAssertEqual(DateUtils.formatRuntime(nil), "N/A")
        XCTAssertEqual(DateUtils.formatRuntime(0), "N/A")
        XCTAssertEqual(DateUtils.formatRuntime(45), "45m")
        XCTAssertEqual(DateUtils.formatRuntime(60), "1h")
        XCTAssertEqual(DateUtils.formatRuntime(90), "1h 30m")
        XCTAssertEqual(DateUtils.formatRuntime(120), "2h")
    }

    func testParseFullDate() {
        let date = DateUtils.parseEpisodeDate("2026-04-20", time: "20:00")
        XCTAssertNotNil(date)
    }

    func testParseEpisodeDateShowNetworkFallback() {
        // When serviceName is nil, parseEpisodeDate should fall back to show.network
        // This is the fix for Apple TV+ / Disney+ showing wrong times
        let show = TVShowDetails(tmdbID: 1)
        show.network = "Apple TV"

        let date = DateUtils.parseEpisodeDate("2026-04-20", for: show)
        XCTAssertNotNil(date)

        let tzET = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tzET
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.hour, 0, "Apple TV+ should resolve to midnight ET via show.network fallback")
        XCTAssertEqual(comps.minute, 0)
    }

    func testParseEpisodeDateDisneyPlusShowNetworkFallback() {
        let show = TVShowDetails(tmdbID: 2)
        show.network = "Disney+"

        let date = DateUtils.parseEpisodeDate("2026-04-20", for: show)
        XCTAssertNotNil(date)

        let tzET = TimeZone(identifier: "America/New_York")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tzET
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.hour, 3, "Disney+ should resolve to 3 AM ET via show.network fallback")
        XCTAssertEqual(comps.minute, 0)
    }

    func testParseEpisodeDateYouTube() {
        // YouTube shows (e.g. Thai dramas): TVMaze airstamp at noon UTC IS the actual release time.
        // The airstamp should be used directly instead of a streaming rule.
        let date = DateUtils.parseEpisodeDate(
            "2026-07-03",
            airstamp: "2026-07-03T12:00:00+00:00",
            serviceName: "YouTube"
        )
        XCTAssertNotNil(date)

        let tzUTC = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tzUTC
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date!)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 7)
        XCTAssertEqual(comps.day, 3, "YouTube airstamp should preserve the TVMaze airdate (Friday)")
        XCTAssertEqual(comps.hour, 12, "YouTube airstamp noon UTC = 7 PM ICT (Thailand)")
        XCTAssertEqual(comps.minute, 0)
    }
}
