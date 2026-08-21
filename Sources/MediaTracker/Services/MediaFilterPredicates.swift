import Foundation
import SwiftData

// MARK: - Predicate Builders (extracted from MediaFilterActor)

enum MediaFilterPredicates {

    /// Builds a compound predicate that combines the category/search predicate with
    /// optional filter fields. Filter evaluation for search and state is pushed to SQLite.
    /// All returned predicates automatically exclude soft-deleted items.
    static func buildFilteredPredicate(
        category: NavigationCategory,
        searchToken: String,
        stateValue: String?,
        badge: String? = nil,
        language: String? = nil
    ) -> Predicate<MediaItem> {
        let hasSearch = !searchToken.isEmpty
        let search = searchToken
        let hasState = stateValue != nil
        let state = stateValue ?? ""
        let typeValueForPredicate = category.rawValue
        let badgeVal = badge
        let langVal = language

        switch category {
        case .upcoming:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedIsUpcoming == true && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.storedIsUpcoming == true && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedIsUpcoming == true && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && $0.storedIsUpcoming == true }

        case .inProgress:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedIsUpcoming == false && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.stateValue == "Active" && $0.storedIsUpcoming == false && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedIsUpcoming == false && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && $0.stateValue == "Active" && $0.storedIsUpcoming == false }

        case .watchlist:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedIsUpcoming == false && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.stateValue == "Wishlist" && $0.storedIsUpcoming == false && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedIsUpcoming == false && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && $0.stateValue == "Wishlist" && $0.storedIsUpcoming == false }

        case .loved:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.tasteValue == "Love" && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.tasteValue == "Love" && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.tasteValue == "Love" && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && $0.tasteValue == "Love" }

        case .completed:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.stateValue == "Completed" && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.stateValue == "Completed" && $0.searchableText.localizedStandardContains(search) && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.stateValue == "Completed" && $0.stateValue == state && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) } }
            return #Predicate { $0.isSoftDeleted == false && $0.stateValue == "Completed" && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) }

        case .archive:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && ($0.stateValue == "On Hold" || $0.stateValue == "Dropped") && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && ($0.stateValue == "On Hold" || $0.stateValue == "Dropped") }

        case .disliked:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.tasteValue == "Dislike" && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.tasteValue == "Dislike" && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.tasteValue == "Dislike" && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && $0.tasteValue == "Dislike" }

        case .binge:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && ($0.storedSmartBadgeLabel == "BINGE" || $0.storedSmartBadgeLabel == "BINGE DROP") && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && ($0.storedSmartBadgeLabel == "BINGE" || $0.storedSmartBadgeLabel == "BINGE DROP") && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && ($0.storedSmartBadgeLabel == "BINGE" || $0.storedSmartBadgeLabel == "BINGE DROP") && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && ($0.storedSmartBadgeLabel == "BINGE" || $0.storedSmartBadgeLabel == "BINGE DROP") }

        case .movie, .tvShow:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.typeValue == typeValueForPredicate && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.typeValue == typeValueForPredicate && $0.searchableText.localizedStandardContains(search) && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.typeValue == typeValueForPredicate && $0.stateValue == state && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) } }
            return #Predicate { $0.isSoftDeleted == false && $0.typeValue == typeValueForPredicate && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) }

        case .catchUp:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel == "BEHIND" && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel == "BEHIND" && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel == "BEHIND" && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel == "BEHIND" }

        case .quickBites:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && (($0.cachedRuntime ?? 0) > 0 || ($0.cachedEpisodeRuntime ?? 0) > 0) && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && (($0.cachedRuntime ?? 0) > 0 || ($0.cachedEpisodeRuntime ?? 0) > 0) && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && (($0.cachedRuntime ?? 0) > 0 || ($0.cachedEpisodeRuntime ?? 0) > 0) && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && (($0.cachedRuntime ?? 0) > 0 || ($0.cachedEpisodeRuntime ?? 0) > 0) }

        case .smartUpcoming:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel == "PREMIERE" && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel == "PREMIERE" && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel == "PREMIERE" && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel == "PREMIERE" }

        case .releaseRadar:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel != nil && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel != nil && $0.searchableText.localizedStandardContains(search) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel != nil && $0.stateValue == state } }
            return #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel != nil }

        case .onThisWeek:
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.releaseDate != nil && $0.searchableText.localizedStandardContains(search) } }
            return #Predicate { $0.isSoftDeleted == false && $0.releaseDate != nil }

        default:
            if hasSearch && hasState { return #Predicate { $0.isSoftDeleted == false && $0.stateValue == state && $0.searchableText.localizedStandardContains(search) && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) } }
            if hasSearch { return #Predicate { $0.isSoftDeleted == false && $0.searchableText.localizedStandardContains(search) && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) } }
            if hasState { return #Predicate { $0.isSoftDeleted == false && $0.stateValue == state && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) } }
            return #Predicate { $0.isSoftDeleted == false && (badgeVal == nil || $0.storedSmartBadgeLabel == badgeVal) && (langVal == nil || $0.cachedLanguage == langVal) }
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
                item.isSoftDeleted == false &&
                ids.contains(item.id) && item.stateValue == state
            }
        } else {
            return #Predicate<MediaItem> { item in
                item.isSoftDeleted == false &&
                ids.contains(item.id)
            }
        }
    }

    static func hiddenStudiosSet() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: UserDefaultsKeys.hiddenStudios.rawValue) ?? ""
        return Set(raw.commaSeparatedValues.map { $0.lowercased() })
    }
}
