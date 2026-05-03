import Foundation
import SwiftData

struct MediaThumbnailMetadata: Sendable, Identifiable {
    let id: PersistentIdentifier
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
        if type == .movie { return year }
        return "\(year) • \(watchProgress ?? "")"
    }

    init(item: MediaItem, recommendationReason: String? = nil) {
        self.id = item.persistentModelID
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
        limit: Int = 40,
        offset: Int = 0
    ) throws -> PaginatedResult {

        let now = Date()
        let processedSearch = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        
        // 1. Optimized Predicate (Compiler Friendly)
        let basePredicate = buildBasePredicate(category: category)
        
        var descriptor = FetchDescriptor<MediaItem>(predicate: basePredicate)
        applySortOrder(to: &descriptor, category: category, sortOrder: sortOrder)
        
        // Pagination only if no complex Swift-level filters
        let hasComplexFilters = !processedSearch.isEmpty || (network != nil && !network!.isEmpty) || (language != nil && !language!.isEmpty) || (genre != nil && !genre!.isEmpty)
        
        if !hasComplexFilters && groupBy == .none {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        
        var results = try modelContext.fetch(descriptor)
        
        // 2. Swift-Level Refinement
        results = refineResults(results, network: network, language: language, genre: genre, searchText: processedSearch)

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
        } else if category == .upcoming {
            featuredUpcoming = results.prefix(15).map { toMetadata($0) }
            results = Array(results.dropFirst(results.count > 15 ? 15 : 0))
        }

        // 4. Grouping Logic
        let finalGroupedItems = groupResults(results, groupBy: groupBy)

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

    private func buildBasePredicate(category: NavigationCategory) -> Predicate<MediaItem> {
        switch category {
        case .upcoming: return buildUpcomingPredicate()
        case .inProgress: return buildInProgressPredicate()
        case .watchlist: return buildWatchlistPredicate()
        case .loved: return buildLovedPredicate()
        case .completed: return buildCompletedPredicate()
        case .archive: return buildArchivePredicate()
        case .disliked: return buildDislikedPredicate()
        case .binge: return buildBingePredicate()
        case .movie, .tvShow: return buildTypePredicate(type: category.rawValue)
        default: return buildDefaultPredicate()
        }
    }

    private func buildUpcomingPredicate() -> Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.storedIsUpcoming == true }
    }

    private func buildInProgressPredicate() -> Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.stateValue == "Active" && $0.storedIsUpcoming == false }
    }

    private func buildWatchlistPredicate() -> Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.stateValue == "Wishlist" && $0.storedIsUpcoming == false }
    }

    private func buildLovedPredicate() -> Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.tasteValue == "Love" }
    }

    private func buildCompletedPredicate() -> Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.stateValue == "Completed" }
    }

    private func buildArchivePredicate() -> Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.stateValue == "On Hold" || $0.stateValue == "Dropped" || $0.stateValue == "Re-watching" }
    }

    private func buildDislikedPredicate() -> Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.tasteValue == "Dislike" }
    }

    private func buildBingePredicate() -> Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.storedSmartBadgeLabel == "BINGE DROP" || $0.storedSmartBadgeLabel == "BINGE" }
    }

    private func buildTypePredicate(type: String) -> Predicate<MediaItem> {
        #Predicate<MediaItem> { $0.typeValue == type }
    }

    private func buildDefaultPredicate() -> Predicate<MediaItem> {
        #Predicate<MediaItem> { _ in true }
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

    private func refineResults(_ results: [MediaItem], network: [String]?, language: String?, genre: String?, searchText: String) -> [MediaItem] {
        var refined = results
        
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

    private func groupResults(_ results: [MediaItem], groupBy: GroupBy) -> [(String, [MediaThumbnailMetadata])] {
        if groupBy == .none { return [] }
        let dict = Dictionary(grouping: results) { item -> String in
            switch groupBy {
            case .genre: return item.cachedGenres.first ?? "Uncategorized"
            case .language: return item.cachedLanguage ?? "Unknown"
            case .network: return item.cachedNetwork ?? "Unknown"
            case .year: return item.releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } } ?? "Unknown"
            case .category: return item.stateValue
            case .none: return ""
            }
        }
        return dict.map { ($0.key, $0.value.map { toMetadata($0) }) }.sorted { $0.0 < $1.0 }
    }

    private func fetchRecentlyAdded(category: NavigationCategory) -> [MediaThumbnailMetadata] {
        if category == .home { return [] }
        var recentDesc = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.stateValue != "Wishlist" })
        recentDesc.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        recentDesc.fetchLimit = 15
        
        if let recentItems = try? modelContext.fetch(recentDesc) {
            return recentItems.filter { !$0.isDeleted }.prefix(10).map { toMetadata($0) }
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
