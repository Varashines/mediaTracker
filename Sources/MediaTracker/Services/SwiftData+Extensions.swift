import SwiftData

extension Sequence where Element: PersistentModel {
    var liveModels: [Element] {
        filter { !$0.isDeleted && $0.modelContext != nil }
    }
}

extension ModelContext {
    /// Saves, reporting a failure instead of discarding it.
    ///
    /// Background actors have no UI to surface into, and `try? …save()` made every
    /// failed write (disk full, unique-constraint merge, iCloud/backing-store error)
    /// completely invisible: no log line, no telemetry, no user signal. The next sync
    /// or heal then ran against a store that had silently kept the old values.
    ///
    /// `SaveCoordinator` remains the only path that raises a user-facing banner; this
    /// is the log for everything else.
    func saveReportingFailure(_ operation: StaticString = #function) {
        do {
            try save()
        } catch {
            AppLogger.error(
                "Save failed in \(operation): \(error.localizedDescription)",
                logger: AppLogger.data
            )
        }
    }
}
