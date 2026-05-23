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
        XCTAssertEqual(comps.day, 21)
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
        XCTAssertEqual(comps.hour, 21)
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
        let item = MediaItem(id: "dummy", title: "Dummy", overview: "")
        let date = DateUtils.parseFullDate(dateString: "2026-04-20", timeString: "20:00", airstamp: nil, timezone: nil, serviceName: nil, item: item)
        XCTAssertNotNil(date)
    }
}
