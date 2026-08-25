import Foundation
import SwiftData

extension MediaFilterActor {
    func applySortOrder(to descriptor: inout FetchDescriptor<MediaItem>, category: NavigationCategory, sortOrder: SortOrder, badge: String? = nil) {
        // Loved always sorts by most recently interacted
        if category == .loved {
            descriptor.sortBy = [
                SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse),
                SortDescriptor<MediaItem>(\.title, order: .forward)
            ]
            return
        }

        if category == .upcoming || category == .smartUpcoming || badge == SmartBadge.premiere.rawValue {
            descriptor.sortBy = [
                SortDescriptor<MediaItem>(\.cachedNextAiringDate, order: .forward),
                SortDescriptor<MediaItem>(\.title, order: .forward)
            ]
        } else {
            switch sortOrder {
            case .alphabetical:
                descriptor.sortBy = [SortDescriptor<MediaItem>(\.title, order: .forward)]
            case .newestRelease:
                descriptor.sortBy = [
                    SortDescriptor<MediaItem>(\.releaseDate, order: .reverse),
                    SortDescriptor<MediaItem>(\.title, order: .forward)
                ]
            case .recentlyAdded:
                descriptor.sortBy = [
                    SortDescriptor<MediaItem>(\.dateAdded, order: .reverse),
                    SortDescriptor<MediaItem>(\.title, order: .forward)
                ]
            case .recentInteraction:
                descriptor.sortBy = [
                    SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse),
                    SortDescriptor<MediaItem>(\.title, order: .forward)
                ]
            }
        }
    }
}
