import Foundation
import os

struct StreamingServiceRule: Codable {
    let patterns: [String]
    let releaseTime: String // "HH:mm"
    let timeZoneIdentifier: String
    let dayOffset: Int
    
    static let defaults: [StreamingServiceRule] = [
        // Apple TV+: Drops at Midnight ET, usually listed as US date but available in India next morning.
        StreamingServiceRule(patterns: ["apple"], releaseTime: "00:00", timeZoneIdentifier: "America/New_York", dayOffset: 0),
        // Disney+ Flagships (Marvel/Star Wars): Drops at 6:00 PM PT / 9:00 PM ET.
        StreamingServiceRule(patterns: ["star wars", "marvel"], releaseTime: "21:00", timeZoneIdentifier: "America/New_York", dayOffset: 0),
        // Disney+ Standard: Drops at Midnight PT / 3:00 AM ET.
        StreamingServiceRule(patterns: ["disney"], releaseTime: "00:00", timeZoneIdentifier: "America/Los_Angeles", dayOffset: 0),
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
    private struct ISOFormatterBox: @unchecked Sendable {
        var formatter: ISO8601DateFormatter?
    }

    private static let formatters = OSAllocatedUnfairLock<[String: DateFormatter]>(uncheckedState: [:])
    private static let isoFormatterInstance = OSAllocatedUnfairLock<ISOFormatterBox>(uncheckedState: ISOFormatterBox(formatter: nil))

    private static func parseISO(_ airstamp: String) -> Date? {
        isoFormatterInstance.withLock { box in
            if box.formatter == nil { box.formatter = ISO8601DateFormatter() }
            return box.formatter?.date(from: airstamp)
        }
    }

    private static func getFormatter(format: String, timeZoneIdentifier: String?) -> DateFormatter {
        let key = "\(format)_\(timeZoneIdentifier ?? "nil")"
        return formatters.withLock { formatters in
            if let formatter = formatters[key] {
                return formatter.copy() as! DateFormatter
            }

            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let tzName = timeZoneIdentifier, let tz = TimeZone(identifier: tzName) {
                formatter.timeZone = tz
            }
            formatters[key] = formatter
            return formatter.copy() as! DateFormatter
        }
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
            if mins == 0 { return pluralizedHoursLabel(hours) }
            return "\(pluralizedHoursLabel(hours)) \(mins)m"
        }
        return "\(minutes)m"
    }

    static func parseEpisodeDate(_ dateString: String?, time: String? = nil, airstamp: String? = nil, timezone: String? = nil, serviceName: String? = nil, for show: TVShowDetails? = nil) -> Date? {
        var resolvedDateString: String?
        if let airstamp = airstamp, airstamp.count >= 10 {
            resolvedDateString = String(airstamp.prefix(10))
        }
        if resolvedDateString == nil {
            resolvedDateString = dateString
        }
        
        let service = (serviceName ?? show?.network ?? "").lowercased()
        let hasRealAirtime = time?.isEmpty == false || show?.nextEpisodeTime?.isEmpty == false
        
        // 1. Streaming service rules: Use when rule matches AND TVMaze has no real airtime.
        //    Streaming originals (Apple TV+, Netflix, etc.) have empty airtime and a placeholder
        //    noon-UTC airstamp. The hardcoded rules provide the actual release time.
        if !hasRealAirtime,
           let rule = StreamingServiceRule.defaults.first(where: { rule in
               rule.patterns.contains(where: { service.contains($0) })
           }), let dateStr = resolvedDateString {
            let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: rule.timeZoneIdentifier)
            if let baseDate = formatter.date(from: "\(dateStr) \(rule.releaseTime)") {
                return Calendar.current.date(byAdding: .day, value: rule.dayOffset, to: baseDate)
            }
        }
        
        // 2. Real TVMaze airtime: Network shows have actual airtime (e.g. "21:00" for HBO).
        //    Use TVMaze date + real airtime + show timezone.
        if hasRealAirtime, let dateStr = resolvedDateString {
            let tzName = timezone ?? show?.timezone
            let timeToUse = time ?? show?.nextEpisodeTime
            if let tName = tzName, let t = timeToUse, TimeZone(identifier: tName) != nil {
                let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: tName)
                if let date = formatter.date(from: "\(dateStr) \(t)") {
                    return date
                }
            }
        }
        
        // 3. Real ISO airstamp: Skip TVMaze's noon-UTC placeholder (T12:00:00+00:00).
        //    YouTube: noon-UTC airstamp IS the actual release time (e.g., 7 PM ICT for Thai shows).
        if let airstamp = airstamp,
           (service == "youtube" || !airstamp.contains("T12:00:00+00:00")),
           let date = parseISO(airstamp) {
            return date
        }
        
        guard let dateStr = resolvedDateString else { return nil }

        // 4. Timezone + time fallback
        if let tzName = timezone ?? show?.timezone, TimeZone(identifier: tzName) != nil {
            let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: tzName)
            let timeToUse = time ?? show?.nextEpisodeTime ?? "20:00"
            return formatter.date(from: "\(dateStr) \(timeToUse)")
        } 
        
        // 5. US 8 PM ET fallback
        let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: "America/New_York")
        return formatter.date(from: "\(dateStr) 20:00")
    }

    static func sameMonthDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        let aComps = calendar.dateComponents([.month, .day], from: a)
        let bComps = calendar.dateComponents([.month, .day], from: b)
        return aComps.month == bComps.month && aComps.day == bComps.day
    }
}
