import Foundation

enum MediaRefreshPolicy {
    static func refreshInterval(for status: String?, type: MediaType) -> TimeInterval? {
        let normalized = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "ended", "canceled", "cancelled":
            // Nothing further will be published — never spend a request on these.
            return nil
        case "returning series", "in production", "post production", "planned":
            // The weekly tier exists for episodic drift (new episodes, corrected
            // air dates), which only TV shows can have. A movie carrying one of
            // these labels is metadata-stable, so it stays on the monthly cadence
            // instead of burning 4× the requests.
            return type == .tvShow ? .days7 : .days30
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
