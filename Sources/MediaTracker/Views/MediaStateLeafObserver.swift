import SwiftData
import SwiftUI

/// Leaf observer for MediaStateService invalidation counters. Reads the
/// counters only in its own body so ticks re-evaluate this view — not the
/// whole parent tree. Must not take observed objects as stored
/// properties; communication is via closures only.
struct MediaStateLeafObserver: View {
    var onSingleItemUpdate: ((PersistentIdentifier) -> Void)? = nil
    var onFullRefresh: (() -> Void)? = nil
    var onRefreshedItem: ((String?) -> Void)? = nil
    var onDiscoveryResync: (() -> Void)? = nil
    var onTasteChange: (() -> Void)? = nil
    var onRecommendationsRefreshed: (() -> Void)? = nil

    var body: some View {
        EmptyView()
            .onChange(of: MediaStateService.shared.needsSingleItemUpdateCount) { _, _ in
                if let itemID = MediaStateService.shared.lastChangedItemID {
                    onSingleItemUpdate?(itemID)
                }
            }
            .onChange(of: MediaStateService.shared.needsFullRefreshCount) { _, _ in
                onFullRefresh?()
            }
            .onChange(of: MediaStateService.shared.refreshedItemID) { _, newID in
                onRefreshedItem?(newID)
            }
            .onChange(of: MediaStateService.shared.discoveryResyncCount) { _, _ in
                onDiscoveryResync?()
            }
            .onChange(of: MediaStateService.shared.tasteChangedCount) { _, _ in
                onTasteChange?()
            }
            .onChange(of: MediaStateService.shared.recommendationsRefreshedCount) { _, _ in
                onRecommendationsRefreshed?()
            }
    }
}
