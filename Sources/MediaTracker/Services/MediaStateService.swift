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

    // Debounce taste cache invalidation — avoid full library re-scan on rapid state changes
    private var tasteCacheDebounceTask: Task<Void, Never>?

    func postMediaStateChanged(itemID: PersistentIdentifier? = nil) {
        if let itemID {
            needsSingleItemUpdateCount += 1
            lastChangedItemID = itemID
        } else {
            needsFullRefreshCount += 1
            lastChangedItemID = nil
        }
        debouncedTasteClear()
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
        debouncedTasteClear()
    }

    func postBulkRefreshed() {
        needsFullRefreshCount += 1
        lastChangedItemID = nil
        debouncedTasteClear()
    }

    /// Debounce taste cache clear — coalesce rapid state changes into a single invalidation
    private func debouncedTasteClear() {
        tasteCacheDebounceTask?.cancel()
        tasteCacheDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            TasteActor.clearCache()
        }
    }
}
