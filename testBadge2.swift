import Foundation

let now = Date()
let targetDate = Calendar.current.date(byAdding: .hour, value: 12, to: now)!
let daysSinceAir = now.timeIntervalSince(targetDate) / 86400
print("daysSinceAir = \(daysSinceAir)")
print("isVeryRecent = \(daysSinceAir >= -1 && daysSinceAir <= 7)")
