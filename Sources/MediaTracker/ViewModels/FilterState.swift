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
    var selectedNetworks: [String] = []
    var selectedLanguages: [String] = []
    var selectedGenres: [String] = []
    var selectedYears: [String] = []
    var selectedStates: [MediaState] = []
    var selectedProviders: [String] = []
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
        selectedNetworks.removeAll()
        selectedLanguages.removeAll()
        selectedGenres.removeAll()
        selectedYears.removeAll()
        selectedStates.removeAll()
        selectedProviders.removeAll()
    }
}
