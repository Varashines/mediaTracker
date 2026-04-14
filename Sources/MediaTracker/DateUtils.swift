import Foundation

struct DateUtils {
    private static let yearMonthDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private static let fullDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        return yearMonthDayFormatter.date(from: dateString)
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
        let isNetflix = service.contains("netflix")
        let isDisney = service.contains("disney")
        let isApple = service.contains("apple")
        let isAmazon = service.contains("amazon") || service.contains("prime")
        let isHulu = service.contains("hulu")
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        // 2. Aggressive Streaming Overrides (Force global release times)
        if isApple {
            // Apple TV+: Drops at Midnight ET (9:30 AM IST).
            // API often lists US date (Thursday), which is already Friday morning in India.
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            if let baseDate = formatter.date(from: "\(dateString) 00:00") {
                return Calendar.current.date(byAdding: .day, value: 1, to: baseDate)
            }
        } else if isDisney {
            // Disney+ (Marvel/Star Wars): Drops at 6:00 PM PT / 9:00 PM ET (6:30 AM IST).
            // 9 PM ET on Tuesday is 6:30 AM IST on Wednesday (Next Day), so no manual offset needed.
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            return formatter.date(from: "\(dateString) 21:00")
        } else if isNetflix {
            // Netflix: Midnight PT (12:30 PM IST).
            formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
            return formatter.date(from: "\(dateString) 00:00")
        } else if isAmazon {
            // Amazon Prime: Midnight GMT (5:30 AM IST)
            formatter.timeZone = TimeZone(identifier: "GMT")
            return formatter.date(from: "\(dateString) 00:00")
        } else if isHulu {
            // Hulu: Midnight ET (9:30 AM IST)
            formatter.timeZone = TimeZone(identifier: "America/New_York")
            return formatter.date(from: "\(dateString) 00:00")
        }

        // 3. Fallback: Trust high-precision ISO airstamp if available (Great for HBO, AMC, etc.)
        if let airstamp = airstamp, let date = isoFormatter.date(from: airstamp) {
            return date
        }

        // 4. Manual fallback to provided timezone or UTC
        if let tzName = timezone ?? show?.timezone, let tz = TimeZone(identifier: tzName) {
            formatter.timeZone = tz
            let timeToUse = time ?? show?.nextEpisodeTime ?? "20:00"
            return formatter.date(from: "\(dateString) \(timeToUse)")
        }

        // 6. Final raw date fallback
        let dateOnlyFormatter = DateFormatter()
        dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
        return dateOnlyFormatter.date(from: dateString)
    }
}
