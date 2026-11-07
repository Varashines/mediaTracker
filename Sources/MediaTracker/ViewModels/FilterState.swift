import SwiftUI

enum SearchType: String, CaseIterable {
    case all = "All"
    case movie = "Movies"
    case tvShow = "TV Shows"
    case castCrew = "Cast & Crew"
}

/// Which half of the search results the user wants to see. `all` renders the
/// library section above the TMDB section; `online` hides the library matches so
/// the results are only titles the user does not own yet.
enum SearchSourceFilter: String, CaseIterable {
    case all = "All Results"
    case online = "Online Only"
}

@Observable @MainActor
class FilterState {
    var selectedCategory: NavigationCategory = .home
    var searchText: String = ""
    var selectedNetworks: [String] = []
    var selectedLanguages: [String] = []
    var selectedGenres: [String] = []
    var selectedYears: [String] = []
    var selectedStates: [MediaState] = []
    var selectedProviders: [String] = []
    var searchTypeFilter: SearchType = .all
    var searchSourceFilter: SearchSourceFilter = .all
    var discoveryRefreshTrigger: Int = 0
    var categorySortOrders: [NavigationCategory: SortOrder] = [:]
    var categoryGroupBys: [NavigationCategory: GroupBy] = [:]

    var currentSortOrder: SortOrder {
        categorySortOrders[selectedCategory] ?? .alphabetical
    }

    var currentGroupBy: GroupBy {
        if selectedCategory == .onThisWeek { return .dayOfWeek }
        return categoryGroupBys[selectedCategory] ?? .none
    }

    var onChange: (() -> Void)?

    func resetFilters() {
        selectedNetworks.removeAll()
        selectedLanguages.removeAll()
        selectedGenres.removeAll()
        selectedYears.removeAll()
        selectedStates.removeAll()
        selectedProviders.removeAll()
        onChange?()
    }
}
