import SwiftData
import SwiftUI
import Combine

@Observable
@MainActor
class MediaViewModel {
    let filterSubject = PassthroughSubject<Void, Never>()
    var selectedCategory: NavigationCategory = .home
    var searchText: String = ""
    var navigationPath = NavigationPath()
    var searchSubmitTrigger: Int = 0

    // Per-category view settings
    var categorySortOrders: [NavigationCategory: SortOrder] = [:]
    var categoryGroupBys: [NavigationCategory: GroupBy] = [:]

    var currentSortOrder: SortOrder {
        return categorySortOrders[selectedCategory] ?? .alphabetical
    }

    var currentGroupBy: GroupBy {
        return categoryGroupBys[selectedCategory] ?? .none
    }

    var selectedNetworks: [String]? = nil
    var selectedLanguage: String? = nil
    var selectedGenre: String? = nil
    var selectedYear: String? = nil
    var selectedState: MediaState? = nil
    
    var isBatchRefreshing: Bool = false
    var isInitialLoading: Bool = true  // Track first load
    var discoveryRefreshTrigger: Int = 0  // NEW: Trigger for Discovery Hub refresh

    // Pagination State
    var totalItemCount: Int = 0
    var currentOffset: Int = 0
    let pageSize: Int = 50
    var isLoadingMore: Bool = false
    var isFastScrolling: Bool = false
    var selectedCollectionID: UUID? = nil {
        didSet {
            if selectedCollectionID == nil {
                selectedCollectionName = nil // Clear name when leaving collection
            }
        }
    }
    var selectedCollectionName: String? = nil
    var showingNoteOverlay: Bool = false
    var currentCollectionNote: String = ""

    // Process Data (Main Actor Cache) - NOW USING LIGHTWEIGHT METADATA
    var displayedItems: [MediaThumbnailMetadata] = []
    var recentlyAddedItems: [MediaThumbnailMetadata] = []
    var homeContinueWatchingItems: [MediaThumbnailMetadata] = []
    var spotlightHero: MediaThumbnailMetadata? = nil
    var groupedItems: [(String, [MediaThumbnailMetadata])] = []
    var recommendations: [MediaThumbnailMetadata] = []
    var featuredUpcomingItems: [MediaThumbnailMetadata] = []

    /// Phase 2 Optimization: O(1) lookup for existing items during search
    var libraryTMDBIDs: Set<String> = []

    // Phase 3: Calendar Cache & Buffer
    var calendarCache: [Date: CalendarResult] = [:]

    // Discovery Cache
    var cachedNetworks: [DiscoveryNode] = []
    var cachedGenres: [DiscoveryNode] = []
    var cachedLanguages: [DiscoveryNode] = []
    var cachedBadges: [DiscoveryNode] = []
    var forYouRecommendations: [MediaThumbnailMetadata] = []
    var lastDiscoveryRefresh: Date?

    func navigationTitle(for category: NavigationCategory) -> String {
        if let colName = selectedCollectionName {
            return colName
        }
        
        if let networks = selectedNetworks, let first = networks.first {
            return networks.count == 1 ? first : "Merged Studios"
        }
        if let lang = selectedLanguage {
            return Locale.current.localizedString(forLanguageCode: lang) ?? lang.uppercased()
        }
        return category.title
    }
}
