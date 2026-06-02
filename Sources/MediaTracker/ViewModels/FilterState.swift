import SwiftUI

@Observable @MainActor
class FilterState {
    var selectedCategory: NavigationCategory = .home
    var searchText: String = ""
    var selectedNetworks: [String]? = nil
    var selectedLanguage: String? = nil
    var selectedGenre: String? = nil
    var selectedYear: String? = nil
    var selectedState: MediaState? = nil
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
