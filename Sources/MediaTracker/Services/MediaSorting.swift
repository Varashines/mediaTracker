import Foundation
import SwiftData

extension MediaFilterActor {
    func sortResults(_ results: inout [MediaItem], category: NavigationCategory, sortOrder: SortOrder) {
        switch sortOrder {
        case .alphabetical:
            results.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .newestRelease:
            results.sort {
                if $0.releaseDate != $1.releaseDate {
                    return ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast)
                }
                return $0.title < $1.title
            }
        case .recentlyAdded:
            results.sort {
                if $0.dateAdded != $1.dateAdded {
                    return ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast)
                }
                return $0.title < $1.title
            }
        case .recentInteraction:
            results.sort {
                if $0.lastInteractionDate != $1.lastInteractionDate {
                    return ($0.lastInteractionDate ?? .distantPast) > ($1.lastInteractionDate ?? .distantPast)
                }
                return $0.title < $1.title
            }
        }
    }

    func applySortOrder(to descriptor: inout FetchDescriptor<MediaItem>, category: NavigationCategory, sortOrder: SortOrder, badge: String? = nil) {
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
