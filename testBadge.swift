import Foundation

let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"
let now = Date()
let targetDate = Calendar.current.date(byAdding: .hour, value: 12, to: now)!
let dateString = formatter.string(from: targetDate)

let airFormatter = DateFormatter()
airFormatter.dateFormat = "yyyy-MM-dd HH:mm"
airFormatter.timeZone = TimeZone(identifier: "America/New_York")
let airDateAsDate = airFormatter.date(from: "\(dateString) 20:00")!

let daysSinceAir = now.timeIntervalSince(airDateAsDate) / 86400
let isVeryRecent = daysSinceAir >= -1 && daysSinceAir <= 7

print("now: \(now)")
print("airDateAsDate: \(airDateAsDate)")
print("daysSinceAir: \(daysSinceAir)")
print("isVeryRecent: \(isVeryRecent)")
