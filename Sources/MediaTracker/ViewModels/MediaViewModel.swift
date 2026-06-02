import SwiftUI
import Combine

struct FilterSnapshot: Sendable {
    let category: NavigationCategory
    let searchText: String
    let sortOrder: SortOrder
    let networks: [String]?
    let language: String?
    let genre: String?
    let year: String?
    let state: MediaState?
    let groupBy: GroupBy
    let collectionID: UUID?

    @MainActor
    init(from viewModel: MediaViewModel) {
        self.category = viewModel.filter.selectedCategory
        self.searchText = viewModel.filter.searchText
        self.sortOrder = viewModel.filter.currentSortOrder
        self.networks = viewModel.filter.selectedNetworks
        self.language = viewModel.filter.selectedLanguage
        self.genre = viewModel.filter.selectedGenre
        self.year = viewModel.filter.selectedYear
        self.state = viewModel.filter.selectedState
        self.groupBy = viewModel.filter.currentGroupBy
        self.collectionID = viewModel.collection.selectedCollectionID
    }
}

@Observable
@MainActor
class MediaViewModel {
    let filterSubject = PassthroughSubject<Void, Never>()
    var navigationPath = NavigationPath()

    var filter = FilterState()
    var pagination = PaginationState()
    var collection = CollectionState()
    var display = DisplayCache()
    var discovery = DiscoveryCache()

    func navigationTitle(for category: NavigationCategory) -> String {
        if let colName = collection.selectedCollectionName {
            return colName
        }
        if let networks = filter.selectedNetworks, let first = networks.first {
            return networks.count == 1 ? first : "Merged Studios"
        }
        if let lang = filter.selectedLanguage {
            return Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
        }
        return category.title
    }

    func purgeSleepCache() {
        display.purgeAll()
        discovery.purgeAll()
    }
}
