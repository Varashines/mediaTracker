import SwiftUI

enum SearchType: String, CaseIterable {
    case all = "All"
    case movie = "Movies"
    case tvShow = "TV Shows"
}

@Observable @MainActor
class FilterState {
    var selectedCategory: NavigationCategory = .home
    var searchText: String = ""
    var selectedNetworks: [String]? = nil
    var selectedLanguage: String? = nil
    var selectedGenre: String? = nil
    var selectedYear: String? = nil
    var selectedState: MediaState? = nil
    var searchTypeFilter: SearchType = .all
    var discoveryRefreshTrigger: Int = 0
    var categorySortOrders: [NavigationCategory: SortOrder] = [:]
    var categoryGroupBys: [NavigationCategory: GroupBy] = [:]

    var currentSortOrder: SortOrder {
        categorySortOrders[selectedCategory] ?? .alphabetical
    }

    var currentGroupBy: GroupBy {
        categoryGroupBys[selectedCategory] ?? .none
    }
}
