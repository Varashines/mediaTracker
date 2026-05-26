import Foundation
import SwiftData

// MARK: - Predicate Builders (extracted from MediaFilterActor)

enum MediaFilterPredicates {

    /// Builds a full predicate incorporating category, search token, and all optional filter fields
    /// that can be pushed down to SQLite. Filters that require Swift-level logic (smart rules,
    /// search text tokenization, releaseRadar/stalled/quickBites date logic) stay in refineResults.
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
                return #Predicate<MediaItem> { item in item.searchableText.localizedStandardContains(searchToken) && item.storedSmartBadgeLabel != nil }
            } else {
                return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel != nil }
            }
        default:
            if hasSearch {
                return #Predicate<MediaItem> { item in item.searchableText.localizedStandardContains(searchToken) }
            } else {
                return #Predicate<MediaItem> { _ in true }
            }
        }
    }

    /// Builds a compound predicate that combines the category/search predicate with
    /// optional filter fields. Filter evaluation for search and state is pushed to SQLite.
    static func buildFilteredPredicate(
        category: NavigationCategory,
        searchToken: String,
        stateValue: String?
    ) -> Predicate<MediaItem> {
        let hasSearch = !searchToken.isEmpty
        let search = searchToken
        let hasState = stateValue != nil
        let state = stateValue ?? ""
        let typeValueForPredicate = category.rawValue

        switch category {
        case .upcoming:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.storedIsUpcoming == true && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.storedIsUpcoming == true && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.storedIsUpcoming == true && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.storedIsUpcoming == true
                }
            }

        case .inProgress:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Active" && item.storedIsUpcoming == false && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Active" && item.storedIsUpcoming == false && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Active" && item.storedIsUpcoming == false && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Active" && item.storedIsUpcoming == false
                }
            }

        case .watchlist:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Wishlist" && item.storedIsUpcoming == false && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Wishlist" && item.storedIsUpcoming == false && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Wishlist" && item.storedIsUpcoming == false && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Wishlist" && item.storedIsUpcoming == false
                }
            }

        case .loved:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.tasteValue == "Love" && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.tasteValue == "Love" && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.tasteValue == "Love" && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.tasteValue == "Love"
                }
            }

        case .completed:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Completed" && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Completed" && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Completed" && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "Completed"
                }
            }

        case .archive:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    (item.stateValue == "On Hold" || item.stateValue == "Dropped" || item.stateValue == "Re-watching") && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    (item.stateValue == "On Hold" || item.stateValue == "Dropped" || item.stateValue == "Re-watching") && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    (item.stateValue == "On Hold" || item.stateValue == "Dropped" || item.stateValue == "Re-watching") && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.stateValue == "On Hold" || item.stateValue == "Dropped" || item.stateValue == "Re-watching"
                }
            }

        case .disliked:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.tasteValue == "Dislike" && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.tasteValue == "Dislike" && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.tasteValue == "Dislike" && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.tasteValue == "Dislike"
                }
            }

        case .binge:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    (item.storedSmartBadgeLabel == "BINGE DROP" || item.storedSmartBadgeLabel == "BINGE") && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    (item.storedSmartBadgeLabel == "BINGE DROP" || item.storedSmartBadgeLabel == "BINGE") && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    (item.storedSmartBadgeLabel == "BINGE DROP" || item.storedSmartBadgeLabel == "BINGE") && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel == "BINGE DROP" || item.storedSmartBadgeLabel == "BINGE"
                }
            }

        case .movie, .tvShow:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.typeValue == typeValueForPredicate && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.typeValue == typeValueForPredicate && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.typeValue == typeValueForPredicate && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.typeValue == typeValueForPredicate
                }
            }

        case .catchUp:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel == "BEHIND" && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel == "BEHIND" && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel == "BEHIND" && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel == "BEHIND"
                }
            }

        case .quickBites:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    ((item.cachedRuntime ?? 0) > 0 || (item.cachedEpisodeRuntime ?? 0) > 0) && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    ((item.cachedRuntime ?? 0) > 0 || (item.cachedEpisodeRuntime ?? 0) > 0) && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    ((item.cachedRuntime ?? 0) > 0 || (item.cachedEpisodeRuntime ?? 0) > 0) && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    (item.cachedRuntime ?? 0) > 0 || (item.cachedEpisodeRuntime ?? 0) > 0
                }
            }

        case .stalled:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    (item.stateValue == "Active" || item.stateValue == "On Hold" || item.stateValue == "Dropped") && item.storedIsUpcoming == false && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    (item.stateValue == "Active" || item.stateValue == "On Hold" || item.stateValue == "Dropped") && item.storedIsUpcoming == false && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    (item.stateValue == "Active" || item.stateValue == "On Hold" || item.stateValue == "Dropped") && item.storedIsUpcoming == false && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    (item.stateValue == "Active" || item.stateValue == "On Hold" || item.stateValue == "Dropped") && item.storedIsUpcoming == false
                }
            }

        case .smartUpcoming:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel == "PREMIERE" && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel == "PREMIERE" && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel == "PREMIERE" && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel == "PREMIERE"
                }
            }

        case .releaseRadar:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel != nil && item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel != nil && item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel != nil && item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    item.storedSmartBadgeLabel != nil
                }
            }

        default:
            if hasSearch && hasState {
                return #Predicate<MediaItem> { item in
                    item.stateValue == state && item.searchableText.localizedStandardContains(search)
                }
            } else if hasSearch {
                return #Predicate<MediaItem> { item in
                    item.searchableText.localizedStandardContains(search)
                }
            } else if hasState {
                return #Predicate<MediaItem> { item in
                    item.stateValue == state
                }
            } else {
                return #Predicate<MediaItem> { item in
                    true
                }
            }
        }
    }

    /// Builds a predicate for manual collections with additional filter support.
    static func buildManualCollectionPredicate(
        itemIDs: [String],
        stateValue: String?
    ) -> Predicate<MediaItem> {
        let ids = itemIDs
        let hasState = stateValue != nil
        let state = stateValue ?? ""

        if hasState {
            return #Predicate<MediaItem> { item in
                ids.contains(item.id) && item.stateValue == state
            }
        } else {
            return #Predicate<MediaItem> { item in
                ids.contains(item.id)
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
            ((item.cachedRuntime ?? 0) > 0 || (item.cachedEpisodeRuntime ?? 0) > 0) && item.stateValue != "Completed"
        }
    }

    static func buildCatchUpPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == "BEHIND" }
    }

    static func buildStalledPredicate() -> Predicate<MediaItem> {
        let active = "Active"
        let onHold = "On Hold"
        let dropped = "Dropped"
        return #Predicate<MediaItem> { item in
            (item.stateValue == active || item.stateValue == onHold || item.stateValue == dropped) && item.storedIsUpcoming == false
        }
    }

    static func buildSmartUpcomingPredicate() -> Predicate<MediaItem> {
        let premiere = "PREMIERE"
        return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == premiere }
    }
}
