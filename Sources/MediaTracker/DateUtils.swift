import Foundation

struct StreamingServiceRule: Codable {
    let patterns: [String]
    let releaseTime: String // "HH:mm"
    let timeZoneIdentifier: String
    let dayOffset: Int
    
    static let defaults: [StreamingServiceRule] = [
        // Apple TV+: Drops at Midnight ET, usually listed as US date but available in India next morning.
        StreamingServiceRule(patterns: ["apple"], releaseTime: "00:00", timeZoneIdentifier: "America/New_York", dayOffset: 1),
        // Disney+ (Marvel/Star Wars): Drops at 6:00 PM PT / 9:00 PM ET.
        StreamingServiceRule(patterns: ["disney"], releaseTime: "21:00", timeZoneIdentifier: "America/New_York", dayOffset: 0),
        // Netflix: Midnight PT.
        StreamingServiceRule(patterns: ["netflix"], releaseTime: "00:00", timeZoneIdentifier: "America/Los_Angeles", dayOffset: 0),
        // Amazon Prime: Midnight GMT.
        StreamingServiceRule(patterns: ["amazon", "prime"], releaseTime: "00:00", timeZoneIdentifier: "GMT", dayOffset: 0),
        // Hulu: Midnight ET.
        StreamingServiceRule(patterns: ["hulu"], releaseTime: "00:00", timeZoneIdentifier: "America/New_York", dayOffset: 0)
    ]
}

struct DateUtils {
    static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
    
    static func formatRuntime(_ minutes: Int?) -> String {
        guard let minutes = minutes, minutes > 0 else { return "N/A" }
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins == 0 { return "\(hours)h" }
            return "\(hours)h \(mins)m"
        }
        return "\(minutes)m"
    }

    static func parseFullDate(dateString: String, timeString: String, airstamp: String?, timezone: String?, serviceName: String?, item: MediaItem) -> Date? {
        parseEpisodeDate(dateString, time: timeString, airstamp: airstamp, timezone: timezone, serviceName: serviceName)
    }

    static func parseEpisodeDate(_ dateString: String?, time: String? = nil, airstamp: String? = nil, timezone: String? = nil, serviceName: String? = nil, for show: TVShowDetails? = nil) -> Date? {
        guard let dateString = dateString else { return nil }
        let isoFormatter = ISO8601DateFormatter()
        
        // 1. Identify the service explicitly for smart defaults
        let service = (serviceName ?? show?.network ?? "").lowercased()
        
        let formatter = DateFormatter()
        var finalDate: Date? = nil

        // 2. Data-Driven Streaming Overrides
        if let rule = StreamingServiceRule.defaults.first(where: { rule in
            rule.patterns.contains(where: { service.contains($0) })
        }) {
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            formatter.timeZone = TimeZone(identifier: rule.timeZoneIdentifier)
            if let baseDate = formatter.date(from: "\(dateString) \(rule.releaseTime)") {
                finalDate = Calendar.current.date(byAdding: .day, value: rule.dayOffset, to: baseDate)
            }
        }

        if finalDate == nil {
            // 3. Fallback: Trust high-precision ISO airstamp if available
            if let airstamp = airstamp, let date = isoFormatter.date(from: airstamp) {
                finalDate = date
            } else if let tzName = timezone ?? show?.timezone, let tz = TimeZone(identifier: tzName) {
                // 4. Manual fallback to provided timezone
                formatter.dateFormat = "yyyy-MM-dd HH:mm"
                formatter.timeZone = tz
                let timeToUse = time ?? show?.nextEpisodeTime ?? "20:00"
                finalDate = formatter.date(from: "\(dateString) \(timeToUse)")
            } else {
                // 5. Final raw date fallback
                let dateOnlyFormatter = DateFormatter()
                dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
                finalDate = dateOnlyFormatter.date(from: dateString)
            }
        }

        return finalDate
    }
}
