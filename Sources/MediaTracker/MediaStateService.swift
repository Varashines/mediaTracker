import SwiftData
import SwiftUI

/// Centralized observable service replacing NotificationCenter-based media state broadcasts.
/// Views observe only the properties they need instead of recomputing on every notification.
@Observable @MainActor
final class MediaStateService {
    static let shared = MediaStateService()
    private init() {}

    // ContentView / LibraryGrid — trigger full library refresh
    private(set) var needsFullRefreshCount = 0

    // DetailView — trigger targeted item refresh
    private(set) var refreshedItemID: String?

    // Any view — update single item in-place
    private(set) var lastChangedItemID: PersistentIdentifier?

    func postMediaStateChanged(itemID: PersistentIdentifier? = nil) {
        needsFullRefreshCount += 1
        lastChangedItemID = itemID
    }

    func postItemRefreshed(id: String, persistentID: PersistentIdentifier? = nil) {
        needsFullRefreshCount += 1
        refreshedItemID = id
        if let persistentID {
            lastChangedItemID = persistentID
        }
    }

    func postBulkRefreshed() {
        needsFullRefreshCount += 1
        lastChangedItemID = nil
    }

    func postTVShowMarkedCompleted() {
        needsFullRefreshCount += 1
    }
}
