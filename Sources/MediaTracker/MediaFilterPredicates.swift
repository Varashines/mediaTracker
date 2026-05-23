import Foundation
import SwiftData

// MARK: - Predicate Builders (extracted from MediaFilterActor)

enum MediaFilterPredicates {

    static func buildBasePredicate(category: NavigationCategory, searchToken: String) -> Predicate<MediaItem> {
        let hasSearch = !searchToken.isEmpty

        switch category {
        case .upcoming: return buildUpcomingPredicate()
        case .inProgress: return buildInProgressPredicate()
        case .watchlist: return buildWatchlistPredicate()
        case .loved: return buildLovedPredicate()
        case .completed: return buildCompletedPredicate()
        case .archive: return buildArchivePredicate()
        case .disliked: return buildDislikedPredicate()
        case .binge: return buildBingePredicate()
        case .movie, .tvShow: return buildTypePredicate(typeString: category.rawValue)
        case .quickBites: return buildQuickBitesPredicate()
        case .catchUp: return buildCatchUpPredicate()
        case .stalled: return buildStalledPredicate()
        case .smartUpcoming: return buildSmartUpcomingPredicate()
        case .releaseRadar:
            if hasSearch {
                return #Predicate<MediaItem> { item in item.searchableText.localizedStandardContains(searchToken) }
            } else {
                return #Predicate<MediaItem> { _ in true }
            }
        default:
            if hasSearch {
                return #Predicate<MediaItem> { item in item.searchableText.localizedStandardContains(searchToken) }
            } else {
                return #Predicate<MediaItem> { _ in true }
            }
        }
    }

    static func buildUpcomingPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.storedIsUpcoming == true }
    }

    static func buildInProgressPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.stateValue == "Active" && item.storedIsUpcoming == false }
    }

    static func buildWatchlistPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.stateValue == "Wishlist" && item.storedIsUpcoming == false }
    }

    static func buildLovedPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.tasteValue == "Love" }
    }

    static func buildCompletedPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.stateValue == "Completed" }
    }

    static func buildArchivePredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.stateValue == "On Hold" || item.stateValue == "Dropped" || item.stateValue == "Re-watching" }
    }

    static func buildDislikedPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.tasteValue == "Dislike" }
    }

    static func buildBingePredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == "BINGE DROP" || item.storedSmartBadgeLabel == "BINGE" }
    }

    static func buildTypePredicate(typeString: String) -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.typeValue == typeString }
    }

    static func buildQuickBitesPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in
            (item.cachedRuntime ?? 0) > 0 || (item.cachedEpisodeRuntime ?? 0) > 0
        }
    }

    static func buildCatchUpPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == "BEHIND" }
    }

    static func buildStalledPredicate() -> Predicate<MediaItem> {
        let active = "Active"
        let onHold = "On Hold"
        let dropped = "Dropped"
        return #Predicate<MediaItem> { item in item.stateValue == active || item.stateValue == onHold || item.stateValue == dropped }
    }

    static func buildSmartUpcomingPredicate() -> Predicate<MediaItem> {
        let premiere = "PREMIERE"
        return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == premiere }
    }
}
