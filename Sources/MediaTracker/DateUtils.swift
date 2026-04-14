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
        let isoFormatter = ISO8601DateFormatter()
        
        // 1. Detect if the time is a known TVMaze placeholder (usually 12:00 PM UTC)
        var isPlaceholder = timeString.isEmpty
        if let airstamp = airstamp, airstamp.contains("T12:00:00+00:00") {
            isPlaceholder = true
        }

        // 2. Identify the service explicitly
        let service = (serviceName ?? item.tvShowDetails?.network ?? "").lowercased()
        let isNetflix = service.contains("netflix")
        let isDisney = service.contains("disney+")
        let isApple = service.contains("apple tv+")
        let isActionDrama = item.overview.lowercased().contains("marvel") || 
                           item.overview.lowercased().contains("star wars") || 
                           item.overview.lowercased().contains("action") ||
                           item.title.lowercased().contains("daredevil")

        // 3. Apply logic
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        if isPlaceholder {
            if isNetflix {
                formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
                return formatter.date(from: "\(dateString) 00:00") // Netflix: 12 AM PT
            } else if isDisney || isApple {
                formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
                let assumedTime = isActionDrama ? "18:00" : "00:00" // Disney+ Marvel: 6 PM PT
                return formatter.date(from: "\(dateString) \(assumedTime)")
            } else {
                // Generic placeholder fallback: Keep UTC but maybe it's actually midnight?
                formatter.timeZone = TimeZone(identifier: "UTC")
                return formatter.date(from: "\(dateString) 00:00")
            }
        }

        // 4. Not a placeholder: Trust the airstamp or manual timezone
        if let airstamp = airstamp, let date = isoFormatter.date(from: airstamp) {
            return date
        }

        if let tzName = timezone, let tz = TimeZone(identifier: tzName) {
            formatter.timeZone = tz
        } else {
            formatter.timeZone = TimeZone(identifier: "UTC")
        }
        return formatter.date(from: "\(dateString) \(timeString)")
    }
}
