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

    // Discovery hub — forced clear + re-sync
    private(set) var discoveryResyncCount = 0

    // DetailView — trigger targeted item refresh
    private(set) var refreshedItemID: String?

    // Any view — update single item in-place
    private(set) var lastChangedItemID: PersistentIdentifier?

    // Debounce derived-cache invalidation — avoid full library re-scans on rapid state changes.
    private var derivedCacheDebounceTask: Task<Void, Never>?

    // Debounce full-refresh broadcasts so rapid state changes (e.g. toggling
    // many episodes) trigger a single library reload instead of one per change.
    private var fullRefreshDebounceTask: Task<Void, Never>?

    func postMediaStateChanged(itemID: PersistentIdentifier? = nil) {
        if let itemID {
            needsSingleItemUpdateCount += 1
            lastChangedItemID = itemID
        } else {
            scheduleDebouncedFullRefresh()
        }
        debouncedDerivedCacheInvalidation()
    }

    func postItemRefreshed(id: String, persistentID: PersistentIdentifier? = nil) {
        if let persistentID {
            needsSingleItemUpdateCount += 1
            refreshedItemID = id
            lastChangedItemID = persistentID
        } else {
            scheduleDebouncedFullRefresh()
            refreshedItemID = id
        }
        debouncedDerivedCacheInvalidation()
    }

    func postBulkRefreshed() {
        scheduleDebouncedFullRefresh()
        debouncedDerivedCacheInvalidation()
    }

    /// Requests a forced re-sync of the Discovery hub (clear + refresh) from any view.
    func requestDiscoveryResync() {
        discoveryResyncCount += 1
        scheduleDebouncedFullRefresh()
    }

    /// Coalesces full-refresh broadcasts within a short window. Single-item
    /// updates are unaffected — only the expensive whole-library reload is debounced.
    private func scheduleDebouncedFullRefresh() {
        fullRefreshDebounceTask?.cancel()
        fullRefreshDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms debounce
            guard !Task.isCancelled else { return }
            needsFullRefreshCount += 1
            lastChangedItemID = nil
        }
    }

    /// Coalesce derived-cache invalidation so rapid state changes clear each
    /// affected aggregate once rather than triggering repeated library scans.
    private func debouncedDerivedCacheInvalidation() {
        derivedCacheDebounceTask?.cancel()
        derivedCacheDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms debounce
            guard !Task.isCancelled else { return }
            TasteActor.clearCache()
            YearReviewCache.shared.invalidate()
            LibraryStatsActor.clearCache()
            ScopedStatsActor.invalidateCache()
        }
    }
}
