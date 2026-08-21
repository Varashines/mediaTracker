import Foundation

/// Single source of truth for in-memory category membership semantics.
///
/// `MediaFilterPredicates.buildFilteredPredicate` mirrors these rules as
/// `#Predicate` macros for database-level fetches — the two cannot share code
/// because `#Predicate` must be a literal. Keep them in sync; parity is
/// covered by `CategoryMatcherParityTests`.
enum MediaCategoryMatcher {
    static func matches(
        _ item: MediaItem,
        category: NavigationCategory,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard !item.isSoftDeleted else { return false }

        switch category {
        case .upcoming:
            return item.storedIsUpcoming
        case .inProgress:
            return item.stateValue == "Active" && item.storedIsUpcoming == false
        case .watchlist:
            return item.stateValue == "Wishlist" && item.storedIsUpcoming == false
        case .loved:
            return item.tasteValue == TasteValue.love.rawValue
        case .disliked:
            return item.tasteValue == TasteValue.dislike.rawValue
        case .completed:
            return item.stateValue == "Completed"
        case .archive:
            return item.stateValue == "On Hold" || item.stateValue == "Dropped"
        case .movie:
            return item.typeValue == MediaType.movie.rawValue
        case .tvShow:
            return item.typeValue == MediaType.tvShow.rawValue
        case .binge:
            return item.storedSmartBadgeLabel == "BINGE DROP" || item.storedSmartBadgeLabel == "BINGE"
        case .catchUp:
            return item.storedSmartBadgeLabel == "BEHIND"
        case .smartUpcoming:
            return item.storedSmartBadgeLabel == "PREMIERE"
        case .onThisWeek:
            guard let releaseDate = item.releaseDate else { return false }
            return DateUtils.sameWeek(releaseDate, now, calendar: calendar)
        case .quickBites:
            if item.typeValue == "Movie" {
                let runtime = item.cachedRuntime ?? 0
                return runtime > 0 && runtime < 90
            } else if item.typeValue == "TV Show" {
                let epRuntime = item.cachedEpisodeRuntime ?? 0
                return epRuntime > 0 && epRuntime < 25
            }
            return false
        default:
            return true
        }
    }
}
