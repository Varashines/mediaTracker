import Foundation
import os

struct StreamingServiceRule: Codable {
    let patterns: [String]
    let releaseTime: String // "HH:mm"
    let timeZoneIdentifier: String
    let dayOffset: Int
    
    static let defaults: [StreamingServiceRule] = [
        // Apple TV Originals are commonly available at 9 PM ET on the evening
        // before their official listed release date.
        StreamingServiceRule(patterns: ["apple"], releaseTime: "21:00", timeZoneIdentifier: "America/New_York", dayOffset: -1),
        // Disney+ Flagships (Marvel/Star Wars): Drops at 6:00 PM PT / 9:00 PM ET.
        StreamingServiceRule(patterns: ["star wars", "marvel"], releaseTime: "21:00", timeZoneIdentifier: "America/New_York", dayOffset: 0),
        // Disney+ Standard: Drops at Midnight PT / 3:00 AM ET.
        StreamingServiceRule(patterns: ["disney"], releaseTime: "00:00", timeZoneIdentifier: "America/Los_Angeles", dayOffset: 0),
        // Netflix: Midnight PT.
        StreamingServiceRule(patterns: ["netflix"], releaseTime: "00:00", timeZoneIdentifier: "America/Los_Angeles", dayOffset: 0),
        // Amazon Prime / MGM+: New 2025/2026 standard is Midnight PT.
        StreamingServiceRule(patterns: ["amazon", "prime", "mgm"], releaseTime: "00:00", timeZoneIdentifier: "America/Los_Angeles", dayOffset: 0),
        // Hulu / Peacock / Paramount+: Mostly Midnight ET on listed date.
        StreamingServiceRule(patterns: ["hulu", "peacock", "paramount"], releaseTime: "00:00", timeZoneIdentifier: "America/New_York", dayOffset: 0),
        // FX / FXX: Broadcasts evening ET / drops next morning on Hulu -> Midnight ET next day.
        StreamingServiceRule(patterns: ["fx", "fxx"], releaseTime: "00:00", timeZoneIdentifier: "America/New_York", dayOffset: 1),
        // HBO Max / Max Originals: 9 PM ET on their listed release date.
        StreamingServiceRule(patterns: ["max"], releaseTime: "21:00", timeZoneIdentifier: "America/New_York", dayOffset: 0),
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

    static func formatWatchTime(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0m" }
        let hours = minutes / 60
        let mins = minutes % 60
        if hours == 0 {
            return "\(mins)m"
        } else if mins == 0 {
            return "\(hours)h"
        } else {
            return "\(hours)h \(mins)m"
        }
    }

    static func formatWatchTimeCompact(minutes: Int) -> String {
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h \(minutes % 60)m"
    }

    static func parseEpisodeDate(_ dateString: String?, time: String? = nil, airstamp: String? = nil, timezone: String? = nil, serviceName: String? = nil, for show: TVShowDetails? = nil) -> Date? {
        let service = (serviceName ?? show?.network ?? "").lowercased()

        // 1. YouTube: Real ISO airstamp from TVMaze (noon-UTC is the actual release time, e.g. 7 PM ICT).
        if service == "youtube", let airstamp = airstamp, let date = parseISO(airstamp) {
            return date
        }

        // Use local broadcast dateString (e.g. "2026-08-23" Sunday) for timezone rules,
        // falling back to airstamp prefix only if dateString is missing.
        let resolvedDateString = dateString ?? (airstamp.flatMap { $0.count >= 10 ? String($0.prefix(10)) : nil })
        let hasRealAirtime = time?.isEmpty == false || show?.nextEpisodeTime?.isEmpty == false
        
        // 2. Streaming service rules: Use when rule matches AND TVMaze has no real broadcast airtime.
        //    Streaming originals (Apple TV+, Hulu, FX, Netflix, etc.) have empty airtime and a placeholder
        //    noon (12:00 UTC or 16:00 UTC) airstamp. The hardcoded rules provide the actual release time.
        if !hasRealAirtime,
           let rule = StreamingServiceRule.defaults.first(where: { rule in
               rule.patterns.contains(where: { service.contains($0) })
           }), let dateStr = resolvedDateString {
            let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: rule.timeZoneIdentifier)
            if let baseDate = formatter.date(from: "\(dateStr) \(rule.releaseTime)") {
                return Calendar.current.date(byAdding: .day, value: rule.dayOffset, to: baseDate)
            }
        }
        
        // 3. Real TVMaze airtime: Network shows have actual airtime (e.g. "21:00" for HBO).
        //    Use TVMaze local airdate + real airtime + show timezone.
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

        // 4. Real ISO airstamp: TVMaze provides exact UTC timestamp for broadcast shows (e.g. 2026-08-24T01:00:00+00:00).
        //    Skip TVMaze's noon-UTC placeholder (T12:00:00+00:00).
        if let airstamp = airstamp,
           !airstamp.contains("T12:00:00+00:00"),
           let date = parseISO(airstamp) {
            return date
        }
        
        guard let dateStr = resolvedDateString else { return nil }

        // 5. Timezone + time fallback
        if let tzName = timezone ?? show?.timezone, TimeZone(identifier: tzName) != nil {
            let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: tzName)
            let timeToUse = time ?? show?.nextEpisodeTime ?? "20:00"
            return formatter.date(from: "\(dateStr) \(timeToUse)")
        } 
        
        // 6. US 8 PM ET fallback
        let formatter = getFormatter(format: "yyyy-MM-dd HH:mm", timeZoneIdentifier: "America/New_York")
        return formatter.date(from: "\(dateStr) 20:00")
    }

    static func sameMonthDay(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        let aComps = calendar.dateComponents([.month, .day], from: a)
        let bComps = calendar.dateComponents([.month, .day], from: b)
        return aComps.month == bComps.month && aComps.day == bComps.day
    }

    static func sameWeek(_ a: Date, _ b: Date, calendar: Calendar = .current) -> Bool {
        let aYear = calendar.component(.year, from: a)
        let bYear = calendar.component(.year, from: b)
        guard aYear != bYear else { return false }

        let aMD = calendar.dateComponents([.month, .day], from: a)
        guard let aMonth = aMD.month, let aDay = aMD.day else { return false }

        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: b))!
        for offset in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let dayMD = calendar.dateComponents([.month, .day], from: dayDate)
            if aMonth == dayMD.month && aDay == dayMD.day { return true }
        }
        return false
    }

    static func weekdayName(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private static let weekdayDisplayFormatterLock = OSAllocatedUnfairLock<[String: DateFormatter]>(uncheckedState: [:])

    private static func getWeekdayDisplayFormatter() -> DateFormatter {
        weekdayDisplayFormatterLock.withLock { formatters in
            let key = "display"
            if let formatter = formatters[key] { return formatter.copy() as! DateFormatter }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEEE, MMM d"
            formatter.timeZone = TimeZone.current
            formatters[key] = formatter
            return formatter.copy() as! DateFormatter
        }
    }

    private static func getWeekdayParseFormatter() -> DateFormatter {
        weekdayDisplayFormatterLock.withLock { formatters in
            let key = "parse"
            if let formatter = formatters[key] { return formatter.copy() as! DateFormatter }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEEE, MMM d"
            formatter.timeZone = TimeZone.current
            formatter.calendar = Calendar(identifier: .gregorian)
            formatters[key] = formatter
            return formatter.copy() as! DateFormatter
        }
    }

    /// Groups a title by the day of the current week whose month+day matches
    /// `date`'s month+day. So a title released on Aug 17, 2018 appears under
    /// "Monday, Aug 17" when the current week's Aug 17 falls on a Monday.
    static func weekdayDisplayString(for date: Date) -> String {
        let calendar = Calendar.current
        let today = Date()
        let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let targetMD = calendar.dateComponents([.month, .day], from: date)
        let formatter = getWeekdayDisplayFormatter()

        for offset in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let dayMD = calendar.dateComponents([.month, .day], from: dayDate)
            if dayMD.month == targetMD.month && dayMD.day == targetMD.day {
                return formatter.string(from: dayDate)
            }
        }
        return "Unknown"
    }

    static func weekdayDisplayDate(for key: String) -> Date {
        getWeekdayParseFormatter().date(from: key) ?? .distantPast
    }
}
