import Foundation
import SwiftData

struct MediaThumbnailMetadata: Sendable, Identifiable, Equatable {
    static func == (lhs: MediaThumbnailMetadata, rhs: MediaThumbnailMetadata) -> Bool {
        return lhs.id == rhs.id && 
               lhs.progress == rhs.progress && 
               lhs.smartBadgeLabel == rhs.smartBadgeLabel &&
               lhs.state == rhs.state
    }
    
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
    let isSparkleBadge: Bool
    let remainingCount: Int?
    let nextAiringDate: Date?
    let genres: [String]
    let recommendationReason: String?
    let lastInteractionDate: Date?

    var versionHash: String { "\(id.hashValue)_\(progress ?? 0)" }

    var formattedMetadata: String {
        let year = releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } } ?? ""
        if let firstGenre = genres.first {
            return "\(year) • \(firstGenre)"
        }
        return year
    }

    init(item: MediaItem, recommendationReason: String? = nil) {
        self.id = item.persistentModelID
        self.itemID = item.id
        self.title = item.title
        self.posterURL = item.posterURL
        self.backdropURL = recommendationReason != nil ? item.backdropURL : nil
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
        self.isSparkleBadge = item.storedSmartBadgeIsSparkle
        self.remainingCount = item.remainingEpisodesCount
        self.nextAiringDate = item.cachedNextAiringDate
        self.recommendationReason = recommendationReason
        self.genres = item.cachedGenres
        self.lastInteractionDate = item.lastInteractionDate
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
        self.isSparkleBadge = false
        self.remainingCount = nil
        self.nextAiringDate = nil
        self.genres = []
        self.recommendationReason = nil
        self.lastInteractionDate = nil
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
        year: String? = nil,
        state: MediaState? = nil,
        badge: String? = nil,
        groupBy: GroupBy = .none,
        collectionID: UUID? = nil,
        limit: Int = 40,
        offset: Int = 0
    ) throws -> PaginatedResult {

        let now = Date()
        let processedSearch = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let searchToken = processedSearch.split(separator: " ").first.map(String.init) ?? ""
        
        // 1. Optimized Predicate (Push filters to SQLite)
        var basePredicate = buildBasePredicate(category: category, searchToken: searchToken)
        var smartRules: [SmartRule] = []
        
        if let cid = collectionID {
            // Check if it's a smart collection
            let colDescriptor = FetchDescriptor<MediaCollection>(predicate: #Predicate { $0.id == cid })
            if let collection = try? modelContext.fetch(colDescriptor).first, collection.isSmart {
                smartRules = collection.smartRules
                // Smart Collections fetch everything to refine in Swift
                basePredicate = #Predicate<MediaItem> { _ in true }
            } else {
                basePredicate = #Predicate<MediaItem> { item in
                    item.collections?.contains { $0.id == cid } ?? false
                }
            }
        }
        
        var descriptor = FetchDescriptor<MediaItem>(predicate: basePredicate)
        applySortOrder(to: &descriptor, category: category, sortOrder: sortOrder, badge: badge)
        
        // Optimization: Skip Swift-level refinement if possible
        let hasComplexFilters = !processedSearch.isEmpty || 
                               (network != nil && !network!.isEmpty) || 
                               (language != nil && !language!.isEmpty) || 
                               (genre != nil && !genre!.isEmpty) ||
                               year != nil ||
                               state != nil ||
                               badge != nil ||
                               category == .releaseRadar ||
                               category == .stalled ||
                               category == .quickBites ||
                               !smartRules.isEmpty
        
        if !hasComplexFilters && groupBy == .none {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        
        var results = try modelContext.fetch(descriptor)
        
        // 2. Swift-Level Refinement
        results = refineResults(results, network: network, language: language, genre: genre, year: year, state: state, badge: badge, searchText: processedSearch, category: category, smartRules: smartRules)

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
            results.sort { 
                if $0.releaseDate != $1.releaseDate {
                    return ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast)
                }
                return $0.title < $1.title
            }
        case .recentlyAdded:
            results.sort { 
                if $0.dateAdded != $1.dateAdded {
                    return ($0.dateAdded ?? .distantPast) > ($1.dateAdded ?? .distantPast)
                }
                return $0.title < $1.title
            }
        case .recentInteraction:
            results.sort { 
                if $0.lastInteractionDate != $1.lastInteractionDate {
                    return ($0.lastInteractionDate ?? .distantPast) > ($1.lastInteractionDate ?? .distantPast)
                }
                return $0.title < $1.title
            }
        }
    }

    private func buildBasePredicate(category: NavigationCategory, searchToken: String) -> Predicate<MediaItem> {
        let hasSearch = !searchToken.isEmpty

        switch category {
        case .upcoming: return buildUpcomingPredicate()
        case .inProgress: return buildInProgressPredicate()
        case .watchlist: return buildWatchlistPredicate()
        case .loved: return buildLovedPredicate()
        case .completed: return buildCompletedPredicate()
        case .archive: return buildArchivePredicate()
        case .disliked: return buildDislikedPredicate()
        case .binge: return buildBingePredicate()
        case .movie, .tvShow: return buildTypePredicate(typeString: category.rawValue)
        case .quickBites: return buildQuickBitesPredicate()
        case .catchUp: return buildCatchUpPredicate()
        case .stalled: return buildStalledPredicate()
        case .smartUpcoming: return buildSmartUpcomingPredicate()
        case .releaseRadar:
            // Complex logical ORs in Predicates often cause compiler timeouts.
            // We'll fetch all and refine in Swift.
            if hasSearch {
                return #Predicate<MediaItem> { item in item.searchableText.localizedStandardContains(searchToken) }
            } else {
                return #Predicate<MediaItem> { _ in true }
            }
        default:
            if hasSearch {
                return #Predicate<MediaItem> { item in item.searchableText.localizedStandardContains(searchToken) }
            } else {
                return #Predicate<MediaItem> { _ in true }
            }
        }
    }

    private func buildUpcomingPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.storedIsUpcoming == true }
    }

    private func buildInProgressPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.stateValue == "Active" && item.storedIsUpcoming == false }
    }

    private func buildWatchlistPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.stateValue == "Wishlist" && item.storedIsUpcoming == false }
    }

    private func buildLovedPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.tasteValue == "Love" }
    }

    private func buildCompletedPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.stateValue == "Completed" }
    }

    private func buildArchivePredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.stateValue == "On Hold" || item.stateValue == "Dropped" || item.stateValue == "Re-watching" }
    }

    private func buildDislikedPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.tasteValue == "Dislike" }
    }

    private func buildBingePredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == "BINGE DROP" || item.storedSmartBadgeLabel == "BINGE" }
    }

    private func buildTypePredicate(typeString: String) -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.typeValue == typeString }
    }

    private func buildQuickBitesPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in 
            (item.cachedRuntime ?? 0) > 0 || (item.cachedEpisodeRuntime ?? 0) > 0
        }
    }

    private func buildCatchUpPredicate() -> Predicate<MediaItem> {
        return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == "CATCH UP" }
    }

    private func buildStalledPredicate() -> Predicate<MediaItem> {
        let active = "Active"
        let onHold = "On Hold"
        let dropped = "Dropped"
        return #Predicate<MediaItem> { item in item.stateValue == active || item.stateValue == onHold || item.stateValue == dropped }
    }

    private func buildSmartUpcomingPredicate() -> Predicate<MediaItem> {
        let premiere = "PREMIERE"
        return #Predicate<MediaItem> { item in item.storedSmartBadgeLabel == premiere }
    }

    private func applySortOrder(to descriptor: inout FetchDescriptor<MediaItem>, category: NavigationCategory, sortOrder: SortOrder, badge: String? = nil) {
        if category == .upcoming || category == .smartUpcoming || badge == "PREMIERE" {
            descriptor.sortBy = [
                SortDescriptor<MediaItem>(\.cachedNextAiringDate, order: .forward),
                SortDescriptor<MediaItem>(\.title, order: .forward)
            ]
        } else {
            switch sortOrder {
            case .alphabetical: 
                descriptor.sortBy = [SortDescriptor<MediaItem>(\.title, order: .forward)]
            case .newestRelease: 
                descriptor.sortBy = [
                    SortDescriptor<MediaItem>(\.releaseDate, order: .reverse),
                    SortDescriptor<MediaItem>(\.title, order: .forward)
                ]
            case .recentlyAdded: 
                descriptor.sortBy = [
                    SortDescriptor<MediaItem>(\.dateAdded, order: .reverse),
                    SortDescriptor<MediaItem>(\.title, order: .forward)
                ]
            case .recentInteraction: 
                descriptor.sortBy = [
                    SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse),
                    SortDescriptor<MediaItem>(\.title, order: .forward)
                ]
            }
        }
    }

    private func refineResults(_ results: [MediaItem], network: [String]?, language: String?, genre: String?, year: String?, state: MediaState?, badge: String?, searchText: String, category: NavigationCategory? = nil, smartRules: [SmartRule] = []) -> [MediaItem] {
        var refined = results
        
        if !smartRules.isEmpty {
            refined = applySmartRules(refined, rules: smartRules)
        }

        if category == .quickBites {
            refined = refined.filter { item in
                if item.typeValue == "Movie" {
                    let runtime = item.cachedRuntime ?? 0
                    return runtime > 0 && runtime < 90
                } else if item.typeValue == "TV Show" {
                    let epRuntime = item.cachedEpisodeRuntime ?? 0
                    return epRuntime > 0 && epRuntime < 25
                }
                return false
            }
        }

        if category == .stalled {
            let ninetyDaysAgo = Date().addingTimeInterval(-90 * 86400)
            refined = refined.filter { item in
                if item.stateValue == "On Hold" || item.stateValue == "Dropped" {
                    return true
                }
                let lastChange = item.lastStateChangeDate ?? .distantPast
                let lastInter = item.lastInteractionDate ?? .distantPast
                return lastChange < ninetyDaysAgo && lastInter < ninetyDaysAgo
            }
        } else if category == .releaseRadar {
            let radarBadges: Set<String> = ["NEW", "BINGE DROP", "PREMIERE", "FINALE", "RECENT"]
            let now = Date()
            refined = refined.filter { item in
                // 1. Must have a valid radar badge
                guard let badge = item.storedSmartBadgeLabel, radarBadges.contains(badge) else { return false }
                
                // 2. Must have already aired/released (Prevents future hype-badges from appearing in the Radar)
                let airDate = item.cachedNextAiringDate ?? item.releaseDate ?? .distantFuture
                return airDate <= now
            }
        }

        if let b = badge {
            refined = refined.filter { $0.storedSmartBadgeLabel == b }
        }

        if let nets = network, !nets.isEmpty {
            let normalizedNets = Set(nets.map { $0.lowercased().trimmingCharacters(in: CharacterSet.whitespaces) })
            refined = refined.filter { item in
                guard let rawNets = item.cachedNetwork else { return false }
                let itemNets = rawNets.components(separatedBy: ",").map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                return itemNets.contains { normalizedNets.contains($0) }
            }
        }
        
        if let lang = language, !lang.isEmpty {
            refined = refined.filter { $0.cachedLanguage == lang }
        }
        
        if let g = genre, !g.isEmpty {
            refined = refined.filter { $0.cachedGenres.contains(g) }
        }

        if let y = year, !y.isEmpty {
            refined = refined.filter { item in
                guard let date = item.releaseDate else { return false }
                let itemYear = Calendar.current.component(.year, from: date)
                return String(itemYear) == y
            }
        }

        if let s = state {
            refined = refined.filter { $0.state == s }
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

    private func applySmartRules(_ items: [MediaItem], rules: [SmartRule]) -> [MediaItem] {
        items.filter { item in
            rules.allSatisfy { rule in
                switch rule {
                case .genre(let g):
                    return item.cachedGenres.contains(g)
                case .releaseYear(let year, let comp):
                    guard let releaseDate = item.releaseDate else { return false }
                    let itemYear = Calendar.current.component(.year, from: releaseDate)
                    switch comp {
                    case .equals: return itemYear == year
                    case .after: return itemYear > year
                    case .before: return itemYear < year
                    }
                case .releaseYearRange(let start, let end):
                    guard let releaseDate = item.releaseDate else { return false }
                    let itemYear = Calendar.current.component(.year, from: releaseDate)
                    return itemYear >= start && itemYear <= end
                case .mediaType(let type):
                    return item.type == type
                case .state(let state):
                    return item.state == state
                case .taste(let taste):
                    return item.taste == taste
                case .badge(let badge):
                    return item.storedSmartBadgeLabel == badge
                }
            }
        }
    }

    private func processHomeCategory(now: Date, totalCount: Int) throws -> PaginatedResult {
        // 1. High Priority Fetch: Split into focused fetches to avoid compiler timeouts and starvation
        
        // Combined Pass A: Items marked as "NEW", "BINGE DROP", "FINALE", or "PREMIERE"
        let newLabel = "NEW"
        let bingeLabel = "BINGE DROP"
        let finaleLabel = "FINALE"
        let premiereLabel = "PREMIERE"
        let dislikeLabel = "Dislike"
        let pStreaming = #Predicate<MediaItem> { item in
            (item.storedSmartBadgeLabel == newLabel || 
             item.storedSmartBadgeLabel == bingeLabel ||
             item.storedSmartBadgeLabel == finaleLabel ||
             item.storedSmartBadgeLabel == premiereLabel) && 
            item.tasteValue != dislikeLabel
        }
        
        // Pass B: Items transitioning from Upcoming to Released (Across entire library)
        // This ensures items that just aired but haven't been "healed" yet are still fetched.
        let distantFuture = Date.distantFuture
        let pTransition = #Predicate<MediaItem> { item in
            item.storedIsUpcoming == true && (
                (item.cachedNextAiringDate ?? distantFuture < now) ||
                (item.releaseDate ?? distantFuture < now)
            )
        }
        
        // Combined Pass C/D: "Active" and "Re-watching" items
        let activeState = "Active"
        let rewatchingState = "Re-watching"
        let pActiveOrRewatching = #Predicate<MediaItem> { item in
            (item.stateValue == activeState || item.stateValue == rewatchingState) &&
            item.tasteValue != dislikeLabel
        }
        
        var descStreaming = FetchDescriptor<MediaItem>(predicate: pStreaming)
        descStreaming.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descStreaming.fetchLimit = 150
        
        var descTransition = FetchDescriptor<MediaItem>(predicate: pTransition)
        descTransition.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descTransition.fetchLimit = 50
        
        var descActiveOrRewatching = FetchDescriptor<MediaItem>(predicate: pActiveOrRewatching)
        descActiveOrRewatching.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descActiveOrRewatching.fetchLimit = 200 // High combined limit
        
        let streamingItems = try modelContext.fetch(descStreaming)
        let transitionItems = try modelContext.fetch(descTransition)
        let activeItemsRaw = try modelContext.fetch(descActiveOrRewatching)
        let rewatchingItems: [MediaItem] = []
        
        // 2. Recent Interaction Fetch: Fill remaining slots with recent Wishlist items
        let recentPredicate = #Predicate<MediaItem> { item in
            item.stateValue == "Wishlist" && item.tasteValue != "Dislike"
        }
        var recentDesc = FetchDescriptor<MediaItem>(predicate: recentPredicate)
        recentDesc.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        recentDesc.fetchLimit = 100
        
        let recentItems = try modelContext.fetch(recentDesc)
        
        // 3. Merge and Deduplicate
        var homeResultsSet = Set<PersistentIdentifier>()
        var homeResults: [MediaItem] = []
        
        // Priority: Streaming > Transition > Active > Rewatching > Recent
        for item in (streamingItems + transitionItems + activeItemsRaw + rewatchingItems + recentItems) {
            if !homeResultsSet.contains(item.persistentModelID) {
                homeResultsSet.insert(item.persistentModelID)
                homeResults.append(item)
            }
        }
        
        let now = Date() // Redefine just to be safe if it was defined above
        let activeItems = homeResults.filter { item in
            // Basic exclusion
            if item.stateValue == "Completed" || item.stateValue == "Dropped" || item.stateValue == "On Hold" { return false }
            if item.storedIsUpcoming { return false }
            
            // Exclude if caught up and next airing is in the future
            let isCaughtUp = (item.remainingEpisodesCount ?? 0) == 0
            let nextAirDate = item.cachedNextAiringDate ?? .distantPast
            if isCaughtUp && nextAirDate > now && item.type == .tvShow {
                return false
            }

            // 1. Items already in progress
            let isCurrentlyWatching = item.stateValue == "Active" || item.stateValue == "Re-watching" || (item.storedProgress ?? 0) > 0
            if isCurrentlyWatching {
                // Staleness check for 0-progress Active/Re-watching items
                if (item.stateValue == "Active" || item.stateValue == "Re-watching") && (item.storedProgress ?? 0) == 0 {
                    let lastInter = item.lastInteractionDate ?? .distantPast
                    let thirtyDaysAgo = now.addingTimeInterval(-30 * 86400)
                    if lastInter < thirtyDaysAgo {
                        return false
                    }
                }
                return true
            }
            
            // 2. Items that JUST released
            let badge = item.storedSmartBadgeLabel
            let isNewDrop = badge == "NEW" || badge == "BINGE DROP" || badge == "FINALE" || badge == "PREMIERE"
            
            if isNewDrop {
                // Wishlist 5-day rule: Hide if in wishlist (0 progress) and released > 5 days ago
                if item.stateValue == "Wishlist" && (item.storedProgress ?? 0) == 0 {
                    let releaseDate = item.cachedNextAiringDate ?? item.releaseDate ?? .distantPast
                    let daysSinceRelease = now.timeIntervalSince(releaseDate) / 86400
                    if daysSinceRelease > 5 {
                        return false
                    }
                }
                return true
            }
            return false
        }.sorted { (itemA: MediaItem, itemB: MediaItem) -> Bool in
            // SORTING: Priority to NEW/BINGE/FINALE/PREMIERE drops first, then currently watching
            let badgeA = itemA.storedSmartBadgeLabel
            let isRecentA = badgeA == "NEW" || badgeA == "BINGE DROP" || badgeA == "FINALE" || badgeA == "PREMIERE"
            let badgeB = itemB.storedSmartBadgeLabel
            let isRecentB = badgeB == "NEW" || badgeB == "BINGE DROP" || badgeB == "FINALE" || badgeB == "PREMIERE"
            
            if isRecentA != isRecentB { return isRecentA }
            
            let isAActive = itemA.stateValue == "Active" || itemA.stateValue == "Re-watching" || (itemA.storedProgress ?? 0) > 0
            let isBActive = itemB.stateValue == "Active" || itemB.stateValue == "Re-watching" || (itemB.storedProgress ?? 0) > 0
            if isAActive != isBActive { return isAActive }
            
            let isAPremiere = itemA.storedSmartBadgeLabel == "PREMIERE"
            let isBPremiere = itemB.storedSmartBadgeLabel == "PREMIERE"
            if isAPremiere != isBPremiere { return isAPremiere }

            let isAStreaming = itemA.storedSmartBadgeLabel == "NEW"
            let isBStreaming = itemB.storedSmartBadgeLabel == "NEW"
            if isAStreaming != isBStreaming { return isAStreaming }
            
            let isAFinale = itemA.storedSmartBadgeLabel == "FINALE"
            let isBFinale = itemB.storedSmartBadgeLabel == "FINALE"
            if isAFinale != isBFinale { return isAFinale }

            let isABinge = itemA.storedSmartBadgeLabel == "BINGE DROP"
            let isBBinge = itemB.storedSmartBadgeLabel == "BINGE DROP"
            if isABinge != isBBinge { return isABinge }
            
            let dateA = itemA.lastInteractionDate ?? .distantPast
            let dateB = itemB.lastInteractionDate ?? .distantPast
            
            if dateA != dateB {
                return dateA > dateB
            }
            
            // Stable sort fallback
            return itemA.title < itemB.title
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
        
        let dict = Dictionary(grouping: results) { item -> String in
            switch groupBy {
            case .genre: return item.cachedGenres.first ?? "Uncategorized"
            case .language: return item.cachedLanguage ?? "Unknown"
            case .network:
                if let rawNetwork = item.cachedNetwork {
                    return rawNetwork.components(separatedBy: ",").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
                }
                return "Unknown"
            case .year: return item.releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } } ?? "Unknown"
            case .category: return item.stateValue
            case .none: return ""
            }
        }
        
        let grouped = dict.map { ($0.key, $0.value.map { toMetadata($0) }) }
        
        return grouped.sorted { $0.0 < $1.0 }
    }

    private func fetchRecentlyAdded(category: NavigationCategory) -> [MediaThumbnailMetadata] {
        if category == .home { return [] }
        var recentDesc = FetchDescriptor<MediaItem>()
        recentDesc.sortBy = [
            SortDescriptor<MediaItem>(\.dateAdded, order: .reverse),
            SortDescriptor<MediaItem>(\.title, order: .forward)
        ]
        recentDesc.fetchLimit = 15
        
        if let recentItems = try? modelContext.fetch(recentDesc) {
            return recentItems.prefix(12).map { toMetadata($0) }
        }
        return []
    }

    func allLibraryTMDBIDs() throws -> Set<String> {
        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = [\.id]
        let items = try modelContext.fetch(descriptor)
        return Set(items.map { $0.id })
    }

    struct LibraryMetadata: Sendable {
        let networks: [DiscoveryNode]
        let genres: [DiscoveryNode]
        let languages: [DiscoveryNode]
    }

    func fetchLibraryMetadata() throws -> LibraryMetadata {
        let netDescriptor = FetchDescriptor<NetworkEntity>(sortBy: [
            SortDescriptor(\.count, order: .reverse),
            SortDescriptor(\.name, order: .forward)
        ])
        let genreDescriptor = FetchDescriptor<GenreEntity>(sortBy: [
            SortDescriptor(\.count, order: .reverse),
            SortDescriptor(\.name, order: .forward)
        ])
        let langDescriptor = FetchDescriptor<LanguageEntity>(sortBy: [
            SortDescriptor(\.count, order: .reverse),
            SortDescriptor(\.code, order: .forward)
        ])

        let nets = (try? modelContext.fetch(netDescriptor)) ?? []
        let hiddenStudios = UserDefaults.standard.string(forKey: "hidden_studios") ?? ""
        let hiddenSet = Set(hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty })
        let filteredNets = nets.filter { !hiddenSet.contains($0.name) && $0.count >= 4 }

        let genres = (try? modelContext.fetch(genreDescriptor)) ?? []
        let langs = (try? modelContext.fetch(langDescriptor)) ?? []

        return LibraryMetadata(
            networks: filteredNets.map { DiscoveryNode(name: $0.name, logoPath: $0.logoPath, count: $0.count, themeColorHex: $0.themeColorHex, sourceNames: $0.sourceNames) },
            genres: genres.map { DiscoveryNode(name: $0.name, logoPath: nil, count: $0.count) },
            languages: langs.map { DiscoveryNode(name: LanguageUtils.languageName(for: $0.code), code: $0.code, logoPath: nil, count: $0.count) }
        )
    }

    func fetchMetadataIfMatches(
        for id: PersistentIdentifier,
        category: NavigationCategory,
        searchText: String,
        network: [String]? = nil,
        language: String? = nil,
        genre: String? = nil,
        year: String? = nil,
        state: MediaState? = nil,
        badge: String? = nil,
        collectionID: UUID? = nil
    ) throws -> MediaThumbnailMetadata? {
        guard let item = modelContext.model(for: id) as? MediaItem else { return nil }
        
        let stringID = item.id
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { $0.id == stringID }
        )
        guard let fetchedItem = try? modelContext.fetch(descriptor).first else { return nil }
        
        if let collectionID = collectionID {
            let collectionDescriptor = FetchDescriptor<MediaCollection>(predicate: #Predicate { $0.id == collectionID })
            if let collection = try? modelContext.fetch(collectionDescriptor).first {
                if !collection.items.contains(where: { $0.id == fetchedItem.id }) {
                    return nil
                }
            }
        }
        
        switch category {
        case .upcoming:
            if !fetchedItem.storedIsUpcoming { return nil }
        case .inProgress:
            if fetchedItem.stateValue != "Active" { return nil }
        case .watchlist:
            if fetchedItem.stateValue != "Wishlist" { return nil }
        case .loved:
            if fetchedItem.tasteValue != "Loved" { return nil }
        case .completed:
            if fetchedItem.stateValue != "Completed" { return nil }
        case .archive:
            if fetchedItem.stateValue != "Archive" { return nil }
        case .disliked:
            if fetchedItem.tasteValue != "Disliked" { return nil }
        case .binge:
            if fetchedItem.storedSmartBadgeLabel != "BINGE DROP" && fetchedItem.storedSmartBadgeLabel != "BINGE" { return nil }
        case .movie:
            if fetchedItem.typeValue != "Movie" { return nil }
        case .tvShow:
            if fetchedItem.typeValue != "TV Show" { return nil }
        case .quickBites:
            let hasRuntime = (fetchedItem.cachedRuntime ?? 0) > 0 || (fetchedItem.cachedEpisodeRuntime ?? 0) > 0
            if !hasRuntime { return nil }
        case .catchUp:
            if fetchedItem.storedSmartBadgeLabel != "CATCH UP" { return nil }
        case .stalled:
            let isStalled = fetchedItem.stateValue == "Active" || fetchedItem.stateValue == "On Hold" || fetchedItem.stateValue == "Dropped"
            if !isStalled { return nil }
        case .smartUpcoming:
            if fetchedItem.storedSmartBadgeLabel != "PREMIERE" { return nil }
        default:
            break
        }
        
        let refined = refineResults(
            [fetchedItem],
            network: network,
            language: language,
            genre: genre,
            year: year,
            state: state,
            badge: badge,
            searchText: searchText,
            category: category
        )
        
        guard let matchingItem = refined.first else { return nil }
        return toMetadata(matchingItem)
    }

    private func toMetadata(_ item: MediaItem) -> MediaThumbnailMetadata {
        MediaThumbnailMetadata(item: item)
    }
}
