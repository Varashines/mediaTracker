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
        StreamingServiceRule(patterns: ["disney", "star wars", "marvel"], releaseTime: "21:00", timeZoneIdentifier: "America/New_York", dayOffset: 0),
        // Netflix: Midnight PT.
        StreamingServiceRule(patterns: ["netflix"], releaseTime: "00:00", timeZoneIdentifier: "America/Los_Angeles", dayOffset: 0),
        // Amazon Prime / MGM+: New 2025/2026 standard is Midnight PT.
        StreamingServiceRule(patterns: ["amazon", "prime", "mgm"], releaseTime: "00:00", timeZoneIdentifier: "America/Los_Angeles", dayOffset: 0),
        // Hulu / Peacock / Paramount+: Mostly Midnight ET.
        StreamingServiceRule(patterns: ["hulu", "peacock", "paramount"], releaseTime: "00:00", timeZoneIdentifier: "America/New_York", dayOffset: 0),
        // Max (Streaming): Midnight PT.
        StreamingServiceRule(patterns: ["max"], releaseTime: "00:00", timeZoneIdentifier: "America/Los_Angeles", dayOffset: 0),
        // HBO (Linear Network): Usually 9 PM ET for flagship releases.
        StreamingServiceRule(patterns: ["hbo"], releaseTime: "21:00", timeZoneIdentifier: "America/New_York", dayOffset: 0)
    ]
}

struct DateUtils {
    private static let formattersLock = NSLock()
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    nonisolated(unsafe) private static var isoFormatterInstance: ISO8601DateFormatter? = nil
    
    private static func getIsoFormatter() -> ISO8601DateFormatter {
        formattersLock.lock()
        defer { formattersLock.unlock() }
        if let formatter = isoFormatterInstance { return formatter }
        let formatter = ISO8601DateFormatter()
        isoFormatterInstance = formatter
        return formatter
    }
    
    private static func getFormatter(format: String, timeZoneIdentifier: String?) -> DateFormatter {
        let key = "\(format)_\(timeZoneIdentifier ?? "nil")"
        formattersLock.lock()
        defer { formattersLock.unlock() }
        
        if let formatter = formatters[key] {
            return formatter
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let tzName = timeZoneIdentifier, let tz = TimeZone(identifier: tzName) {
            formatter.timeZone = tz
        }
        formatters[key] = formatter
        return formatter
    }

    static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        let formatter = getFormatter(format: "yyyy-MM-dd", timeZoneIdentifier: nil)
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
        
        // 1. Identify the service explicitly for smart defaults
        let service = (serviceName ?? show?.network ?? "").lowercased()
        
        var finalDate: Date? = nil

        // 2. Data-Driven Streaming Overrides (Preserve existing strict rules)
        if let rule = StreamingServiceRule.defaults.first(where: { rule in
            rule.patterns.contains(where: { service.contains($0) })
        }) {
            let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: rule.timeZoneIdentifier)
            if let baseDate = formatter.date(from: "\(dateString) \(rule.releaseTime)") {
                finalDate = Calendar.current.date(byAdding: .day, value: rule.dayOffset, to: baseDate)
            }
        }

        if finalDate == nil {
            // 3. Fallback: Trust high-precision ISO airstamp if available from the database
            if let airstamp = airstamp, let date = getIsoFormatter().date(from: airstamp) {
                finalDate = date
            } 
            // 4. Use provided timezone and show-level schedule
            else if let tzName = timezone ?? show?.timezone, TimeZone(identifier: tzName) != nil {
                let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: tzName)
                let timeToUse = time ?? show?.nextEpisodeTime ?? "20:00"
                finalDate = formatter.date(from: "\(dateString) \(timeToUse)")
            } 
            // 5. Smart Fallback for TMDB dates without time: Assume US Network (8 PM ET)
            else {
                let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: "America/New_York")
                finalDate = formatter.date(from: "\(dateString) 20:00")
            }
        }

        return finalDate
    }
}
