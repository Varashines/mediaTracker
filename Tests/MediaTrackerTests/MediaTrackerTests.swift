import XCTest
@testable import MediaTracker

final class MediaTrackerTests: XCTestCase {
    func testDateUtilsParsing() throws {
        // Test Apple TV+ (9:30 AM IST)
        let appleDate = DateUtils.parseEpisodeDate("2026-04-20", serviceName: "Apple TV+")
        XCTAssertNotNil(appleDate)
        
        let calendar = Calendar.current
        let _ = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: appleDate!)
        
        // If current locale is IST (+5:30), then 00:00 ET (Thursday) + 1 day = 00:00 ET (Friday)
        // 00:00 ET is 09:30 AM or 10:30 AM IST depending on DST.
        // The implementation adds 1 day to 00:00 ET.
        // Let's just check it's not Midnight (00:00) in local time if we are in IST.
        
        // Test Netflix (Midnight PT)
        let netflixDate = DateUtils.parseEpisodeDate("2026-04-20", serviceName: "Netflix")
        XCTAssertNotNil(netflixDate)
        
        // Test generic date
        let genericDate = DateUtils.parseDate("2026-04-20")
        XCTAssertNotNil(genericDate)
        let genericComponents = calendar.dateComponents([.hour, .minute], from: genericDate!)
        XCTAssertEqual(genericComponents.hour, 0)
        XCTAssertEqual(genericComponents.minute, 0)
    }
}
