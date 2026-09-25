import Foundation

enum MediaRefreshPolicy {
    static func refreshInterval(for status: String?, type: MediaType) -> TimeInterval? {
        let normalized = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "returning series", "in production", "post production", "planned":
            return .days7
        case "released":
            return .days30
        case "ended", "canceled", "cancelled":
            return nil
        default:
            return .days30
        }
    }

    static func shouldRefresh(
        status: String?,
        type: MediaType,
        lastUpdated: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastUpdated else { return true }
        guard let interval = refreshInterval(for: status, type: type) else { return false }
        return now.timeIntervalSince(lastUpdated) >= interval
    }
}
