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
    private(set) var needsSingleItemUpdateCount = 0

    // DetailView — trigger targeted item refresh
    private(set) var refreshedItemID: String?

    // Any view — update single item in-place
    private(set) var lastChangedItemID: PersistentIdentifier?

    func postMediaStateChanged(itemID: PersistentIdentifier? = nil) {
        // Only trigger full refresh when no specific item is provided (bulk change)
        if let itemID {
            needsSingleItemUpdateCount += 1
            lastChangedItemID = itemID
        } else {
            needsFullRefreshCount += 1
            lastChangedItemID = nil
        }
        TasteActor.clearCache()
    }

    func postItemRefreshed(id: String, persistentID: PersistentIdentifier? = nil) {
        if let persistentID {
            needsSingleItemUpdateCount += 1
            refreshedItemID = id
            lastChangedItemID = persistentID
        } else {
            needsFullRefreshCount += 1
            refreshedItemID = id
            lastChangedItemID = nil
        }
        TasteActor.clearCache()
    }

    func postBulkRefreshed() {
        needsFullRefreshCount += 1
        lastChangedItemID = nil
        TasteActor.clearCache()
    }
}
