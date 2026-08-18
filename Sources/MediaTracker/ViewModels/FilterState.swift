import SwiftUI

enum SearchType: String, CaseIterable {
    case all = "All"
    case movie = "Movies"
    case tvShow = "TV Shows"
    case castCrew = "Cast & Crew"
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
    var selectedProvider: String? = nil
    var searchTypeFilter: SearchType = .all
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

    func resetFilters() {
        selectedNetworks = nil
        selectedLanguage = nil
        selectedGenre = nil
        selectedYear = nil
        selectedState = nil
        selectedProvider = nil
    }
}
