import Foundation
import SwiftData

struct MediaThumbnailMetadata: Sendable, Identifiable {
    let id: PersistentIdentifier
    let itemID: String
    let title: String
    let posterURL: String?
    let backdropURL: String?
    let overview: String
    let releaseDate: Date?
    let type: MediaType?
    let state: MediaState?
    let themeColorHex: String?
    let progress: Double?
    let watchProgress: String?
    let nextEpisodeToWatchLabel: String?
    let isUpcoming: Bool
    let badgeText: String?
    let smartBadgeLabel: String?
    let smartBadgeIcon: String?
    let isSparkleBadge: Bool
    let remainingCount: Int?
    let genres: [String]
    let recommendationReason: String?
    
    var versionHash: String { "\(id.hashValue)_\(progress ?? 0)" }
    
    var formattedMetadata: String {
        let year = releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } } ?? ""
        return year
    }

    init(item: MediaItem, recommendationReason: String? = nil) {
        self.id = item.persistentModelID
        self.itemID = item.id
        self.title = item.title
        self.posterURL = item.posterURL
        self.backdropURL = item.backdropURL
        self.overview = item.overview
        self.releaseDate = item.releaseDate
        self.type = item.type
        self.state = item.state
        self.themeColorHex = item.themeColorHex
        self.progress = item.storedProgress
        self.watchProgress = item.storedWatchProgressLabel
        self.nextEpisodeToWatchLabel = item.storedNextEpisodeLabel
        self.isUpcoming = item.storedIsUpcoming
        self.badgeText = item.gridBadgeText
        self.smartBadgeLabel = item.storedSmartBadgeLabel
        self.smartBadgeIcon = item.storedSmartBadgeIcon
        self.isSparkleBadge = item.storedSmartBadgeIsSparkle
        self.remainingCount = item.remainingEpisodesCount
        self.recommendationReason = recommendationReason
        self.genres = item.cachedGenres
    }

    init(id: PersistentIdentifier, title: String, overview: String) {
        self.id = id
        self.itemID = ""
        self.title = title
        self.overview = overview
        self.posterURL = nil
        self.backdropURL = nil
        self.releaseDate = nil
        self.type = .movie
        self.state = .wishlist
        self.themeColorHex = nil
        self.progress = nil
        self.watchProgress = nil
        self.nextEpisodeToWatchLabel = nil
        self.isUpcoming = false
        self.badgeText = nil
        self.smartBadgeLabel = nil
        self.smartBadgeIcon = nil
        self.isSparkleBadge = false
        self.remainingCount = nil
        self.genres = []
        self.recommendationReason = nil
    }
}

struct PaginatedResult: Sendable {
    let displayed: [MediaThumbnailMetadata]
    let featuredUpcoming: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let homeContinueWatching: [MediaThumbnailMetadata]
    let spotlightHero: MediaThumbnailMetadata?
    let grouped: [(String, [MediaThumbnailMetadata])]
    let totalCount: Int
}

@ModelActor
actor MediaFilterActor {
    func filterAndSort(
        category: NavigationCategory,
        searchText: String,
        sortOrder: SortOrder,
        network: [String]?,
        language: String?,
        genre: String? = nil,
        groupBy: GroupBy = .none,
        collectionID: UUID? = nil,
        limit: Int = 40,
        offset: Int = 0
    ) throws -> PaginatedResult {

        let now = Date()
        let processedSearch = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        
        // 1. Optimized Predicate (Push filters to SQLite)
        var basePredicate = buildBasePredicate(category: category)
        
        if let cid = collectionID {
             basePredicate = #Predicate<MediaItem> { item in
                 item.collections?.contains { $0.id == cid } ?? false
             }
        }
        
        var descriptor = FetchDescriptor<MediaItem>(predicate: basePredicate)
        applySortOrder(to: &descriptor, category: category, sortOrder: sortOrder)
        
        // Optimization: Skip Swift-level refinement if possible
        let hasComplexFilters = !processedSearch.isEmpty || 
                               (network != nil && !network!.isEmpty) || 
                               (language != nil && !language!.isEmpty) || 
                               (genre != nil && !genre!.isEmpty) ||
                               category == .releaseRadar ||
                               category == .stalled
        
        if !hasComplexFilters && groupBy == .none {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        
        var results = try modelContext.fetch(descriptor)
        
        // 2. Swift-Level Refinement
        results = refineResults(results, network: network, language: language, genre: genre, searchText: processedSearch, category: category)

        let totalCount = (hasComplexFilters || groupBy != .none) ? 
                         results.count : 
                         (try? modelContext.fetchCount(FetchDescriptor<MediaItem>(predicate: basePredicate))) ?? results.count
                         
        if hasComplexFilters && groupBy == .none {
            let start = min(offset, results.count)
            let end = min(start + limit, results.count)
            results = Array(results[start..<end])
        }

        var featuredUpcoming: [MediaThumbnailMetadata] = []
        
        // 3. Specialized Logic
        if category == .home {
            let homeResult = try processHomeCategory(now: now, totalCount: totalCount)
            return homeResult
        } else if category == .upcoming && collectionID == nil {
            featuredUpcoming = results.prefix(15).map { toMetadata($0) }
            results = Array(results.dropFirst(results.count > 15 ? 15 : 0))
        }

        // 4. Grouping Logic
        let finalGroupedItems = groupResults(results, groupBy: groupBy, collectionID: collectionID)

        // 5. Fetch Recently Added
        let recentAddedItems = fetchRecentlyAdded(category: category)

        return PaginatedResult(
            displayed: results.map { toMetadata($0) },
            featuredUpcoming: featuredUpcoming,
            recentlyAdded: recentAddedItems,
            homeContinueWatching: [],
            spotlightHero: nil,
            grouped: finalGroupedItems,
            totalCount: totalCount
        )
    }

    private func sortResults(_ results: inout [MediaItem], category: NavigationCategory, sortOrder: SortOrder) {
        switch sortOrder {
        case .alphabetical:
            results.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .newestRelease:
            results.sort { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        case .recentlyAdded:
            results.sort { ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast) }
        }
    }

    private func buildBasePredicate(category: NavigationCategory) -> Predicate<MediaItem> {
        switch category {
        case .upcoming:
            return #Predicate<MediaItem> { item in item.storedIsUpcoming == true }
        case .inProgress:
            return #Predicate<MediaItem> { item in item.stateValue == "Active" && item.storedIsUpcoming == false }
        case .watchlist:
            return #Predicate<MediaItem> { item in item.stateValue == "Wishlist" && item.storedIsUpcoming == false }
        case .loved:
            return #Predicate<MediaItem> { item in item.tasteValue == "Love" }
        case .completed:
            return #Predicate<MediaItem> { item in item.stateValue == "Completed" }
        case .archive:
            return #Predicate<MediaItem> { item in item.stateValue == "On Hold" || item.stateValue == "Dropped" || item.stateValue == "Re-watching" }
        case .disliked:
            return #Predicate<MediaItem> { item in item.tasteValue == "Dislike" }
        case .binge:
            return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == "BINGE DROP" || item.storedSmartBadgeLabel == "BINGE" }
        case .movie, .tvShow:
            let typeString = category.rawValue
            return #Predicate<MediaItem> { item in item.typeValue == typeString }
        case .quickBites:
            return #Predicate<MediaItem> { item in 
                if let runtime = item.cachedRuntime {
                    return runtime > 0 && runtime < 90
                } else {
                    return false
                }
            }
        case .catchUp:
            return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == "CATCH UP" }
        case .stalled:
            return #Predicate<MediaItem> { item in item.stateValue == "Active" }
        case .releaseRadar:
            // Complex logical ORs in Predicates often cause compiler timeouts.
            // We'll fetch all and refine in Swift.
            return #Predicate<MediaItem> { _ in true }
        default:
            return #Predicate<MediaItem> { _ in true }
        }
    }

    private func applySortOrder(to descriptor: inout FetchDescriptor<MediaItem>, category: NavigationCategory, sortOrder: SortOrder) {
        if category == .upcoming {
            descriptor.sortBy = [SortDescriptor<MediaItem>(\.cachedNextAiringDate, order: .forward)]
        } else {
            switch sortOrder {
            case .alphabetical: descriptor.sortBy = [SortDescriptor<MediaItem>(\.title, order: .forward)]
            case .newestRelease: descriptor.sortBy = [SortDescriptor<MediaItem>(\.releaseDate, order: .reverse)]
            case .recentlyAdded: descriptor.sortBy = [SortDescriptor<MediaItem>(\.dateAdded, order: .reverse)]
            }
        }
    }

    private func refineResults(_ results: [MediaItem], network: [String]?, language: String?, genre: String?, searchText: String, category: NavigationCategory? = nil) -> [MediaItem] {
        var refined = results
        
        if category == .stalled {
            let ninetyDaysAgo = Date().addingTimeInterval(-90 * 86400)
            refined = refined.filter { item in
                let lastChange = item.lastStateChangeDate ?? .distantPast
                let lastInter = item.lastInteractionDate ?? .distantPast
                return lastChange < ninetyDaysAgo && lastInter < ninetyDaysAgo
            }
        } else if category == .releaseRadar {
            let radarBadges: Set<String> = ["NEW", "BINGE DROP", "SERIES PREMIERE", "SEASON PREMIERE"]
            refined = refined.filter { item in
                if let badge = item.storedSmartBadgeLabel {
                    return radarBadges.contains(badge)
                }
                return false
            }
        }

        if let nets = network, !nets.isEmpty {
            let normalizedNets = Set(nets.map { $0.lowercased().trimmingCharacters(in: CharacterSet.whitespaces) })
            refined = refined.filter { item in
                guard let itemNet = item.cachedNetwork?.lowercased().trimmingCharacters(in: CharacterSet.whitespaces) else { return false }
                return normalizedNets.contains(itemNet)
            }
        }
        
        if let lang = language, !lang.isEmpty {
            refined = refined.filter { $0.cachedLanguage == lang }
        }
        
        if let g = genre, !g.isEmpty {
            refined = refined.filter { $0.cachedGenres.contains(g) }
        }

        if !searchText.isEmpty {
            let tokens = searchText.split(separator: " ").map(String.init)
            refined = refined.filter { item in
                let target = item.searchableText
                return tokens.allSatisfy { target.contains($0) }
            }
        }
        return refined
    }

    private func processHomeCategory(now: Date, totalCount: Int) throws -> PaginatedResult {
        let homePredicate = #Predicate<MediaItem> { item in
            (item.stateValue == "Active" || item.stateValue == "Wishlist") && item.tasteValue != "Dislike"
        }
        var homeDesc = FetchDescriptor<MediaItem>(predicate: homePredicate)
        homeDesc.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        homeDesc.fetchLimit = 100
        
        let homeResults = try modelContext.fetch(homeDesc)
        
        let activeItems = homeResults.filter { item in
            if item.releaseDate == nil && item.cachedNextAiringDate == nil { return false }
            let isActive = item.stateValue == "Active"
            let isWishlist = item.stateValue == "Wishlist"
            let date = item.cachedNextAiringDate ?? item.releaseDate ?? .distantPast
            let isFuture = date > now
            let badge = item.storedSmartBadgeLabel
            let isRecent = badge == "NEW" || badge == "BINGE DROP"
            return ((isActive || isWishlist) && !isFuture) || isRecent
        }.sorted { (itemA: MediaItem, itemB: MediaItem) -> Bool in
            let isAStreaming = itemA.storedSmartBadgeLabel == "NEW"
            let isBStreaming = itemB.storedSmartBadgeLabel == "NEW"
            if isAStreaming != isBStreaming { return isAStreaming }
            let isABinge = itemA.storedSmartBadgeLabel == "BINGE DROP"
            let isBBinge = itemB.storedSmartBadgeLabel == "BINGE DROP"
            if isABinge != isBBinge { return isABinge }
            return (itemA.lastInteractionDate ?? .distantPast) > (itemB.lastInteractionDate ?? .distantPast)
        }
        
        // Find Spotlight Hero: Most recently interacted "Active" item
        let spotlight = activeItems.first { $0.stateValue == "Active" }
        
        let homeContinueWatching = activeItems.prefix(20).map { toMetadata($0) }
        
        let comingSoonItems = homeResults.filter { item in
            let airDate = item.cachedNextAiringDate ?? .distantPast
            return airDate > now
        }.sorted { ($0.cachedNextAiringDate ?? .distantPast) < ($1.cachedNextAiringDate ?? .distantPast) }
        
        return PaginatedResult(
            displayed: [], 
            featuredUpcoming: [], 
            recentlyAdded: [], 
            homeContinueWatching: homeContinueWatching,
            spotlightHero: spotlight.map { toMetadata($0) },
            grouped: [("Coming Soon", comingSoonItems.prefix(20).map { toMetadata($0) })], 
            totalCount: totalCount
        )
    }

    private func groupResults(_ results: [MediaItem], groupBy: GroupBy, collectionID: UUID? = nil) -> [(String, [MediaThumbnailMetadata])] {
        if groupBy == .none { return [] }
        
        var completedIDs: Set<String> = []
        if let cid = collectionID {
            let colDescriptor = FetchDescriptor<MediaCollection>(predicate: #Predicate { $0.id == cid })
            if let collection = try? modelContext.fetch(colDescriptor).first {
                completedIDs = Set(collection.completedItemIDs)
            }
        }

        let dict = Dictionary(grouping: results) { item -> String in
            switch groupBy {
            case .genre: return item.cachedGenres.first ?? "Uncategorized"
            case .language: return item.cachedLanguage ?? "Unknown"
            case .network: return item.cachedNetwork ?? "Unknown"
            case .year: return item.releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } } ?? "Unknown"
            case .category: return item.stateValue
            case .kanban: return completedIDs.contains(item.id) ? "Watched" : "To Watch"
            case .none: return ""
            }
        }
        
        let grouped = dict.map { ($0.key, $0.value.map { toMetadata($0) }) }
        
        if groupBy == .kanban {
            return grouped.sorted { a, b in
                if a.0 == "To Watch" { return true }
                if b.0 == "To Watch" { return false }
                return a.0 < b.0
            }
        }
        
        return grouped.sorted { $0.0 < $1.0 }
    }

    private func fetchRecentlyAdded(category: NavigationCategory) -> [MediaThumbnailMetadata] {
        if category == .home { return [] }
        var recentDesc = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.stateValue != "Wishlist" })
        recentDesc.sortBy = [SortDescriptor<MediaItem>(\.dateAdded, order: .reverse)]
        recentDesc.fetchLimit = 15
        
        if let recentItems = try? modelContext.fetch(recentDesc) {
            return recentItems.prefix(10).map { toMetadata($0) }
        }
        return []
    }

    func allLibraryTMDBIDs() throws -> Set<String> {
        let descriptor = FetchDescriptor<MediaItem>()
        let items = try modelContext.fetch(descriptor)
        return Set(items.map { $0.id })
    }

    private func toMetadata(_ item: MediaItem) -> MediaThumbnailMetadata {
        MediaThumbnailMetadata(item: item)
    }
}
