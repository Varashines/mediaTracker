import Foundation
import SwiftData
import os

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
        self.backdropURL = item.backdropURL
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
    init(id: PersistentIdentifier, title: String) {
        self.id = id
        self.itemID = ""
        self.title = title
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
    
    /// Preview/test initializer with full control over all fields
    init(
        id: PersistentIdentifier,
        title: String,
        type: MediaType = .movie,
        state: MediaState = .wishlist,
        smartBadgeLabel: String? = nil,
        isSparkleBadge: Bool = false,
        progress: Double? = nil,
        remainingCount: Int? = nil,
        isUpcoming: Bool = false,
        themeColorHex: String? = nil,
        posterURL: String? = nil
    ) {
        self.id = id
        self.itemID = ""
        self.title = title
        self.posterURL = posterURL
        self.backdropURL = nil
        self.releaseDate = nil
        self.type = type
        self.state = state
        self.themeColorHex = themeColorHex
        self.progress = progress
        self.watchProgress = nil
        self.nextEpisodeToWatchLabel = nil
        self.isUpcoming = isUpcoming
        self.badgeText = nil
        self.smartBadgeLabel = smartBadgeLabel
        self.isSparkleBadge = isSparkleBadge
        self.remainingCount = remainingCount
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
        // Pre-compute filter values for Swift-level refinement
        let stateRaw = state?.rawValue

        // 1. Handle collection override first
        var smartRules: [SmartRule] = []
        var basePredicate: Predicate<MediaItem>

        if let cid = collectionID {
            let colDescriptor = FetchDescriptor<MediaCollection>(predicate: #Predicate { $0.id == cid })
            if let collection = try? modelContext.fetch(colDescriptor).first, collection.isSmart {
                smartRules = collection.smartRules
                basePredicate = MediaFilterPredicates.buildFilteredPredicate(
                    category: category, searchToken: searchToken, stateValue: stateRaw, badge: badge, language: language
                )
            } else if let collection = try? modelContext.fetch(colDescriptor).first {
                let itemIDs = collection.items.compactMap { $0.id }
                if itemIDs.isEmpty {
                    basePredicate = #Predicate<MediaItem> { _ in false }
                } else {
                    basePredicate = MediaFilterPredicates.buildManualCollectionPredicate(
                        itemIDs: itemIDs, stateValue: stateRaw
                    )
                }
            } else {
                basePredicate = MediaFilterPredicates.buildFilteredPredicate(
                    category: category, searchToken: searchToken, stateValue: stateRaw, badge: badge, language: language
                )
            }
        } else {
            basePredicate = MediaFilterPredicates.buildFilteredPredicate(
                category: category, searchToken: searchToken, stateValue: stateRaw, badge: badge, language: language
            )
        }

        var descriptor = FetchDescriptor<MediaItem>(predicate: basePredicate)
        descriptor.propertiesToFetch = [
            \.id, \.title, \.posterURL, \.backdropURL, \.releaseDate,
            \.typeValue, \.stateValue, \.tasteValue, \.themeColorHex,
            \.lastInteractionDate, \.lastStateChangeDate, \.dateAdded, \.lastUpdated,
            \.cachedGenres, \.cachedCreators, \.cachedLanguage, \.cachedNetwork,
            \.cachedNetworkLogoPath, \.cachedNextAiringDate, \.cachedRuntime,
            \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount, \.remainingEpisodesCount,
            \.storedSmartBadgeLabel, \.storedSmartBadgeIsSparkle, \.storedIsUpcoming,
            \.storedNextEpisodeLabel, \.storedWatchProgressLabel, \.storedProgress,
            \.searchableText
        ]
        applySortOrder(to: &descriptor, category: category, sortOrder: sortOrder, badge: badge)

        // Optimization: Only use SQLite pagination when no Swift-level refinement is needed.
        // Swift-level refinement is now only needed for network (array of strings), genre (transformable array), stalled/quickBites/releaseRadar category date limits, or custom smart rules.
        let needsSwiftRefinement = (network?.isEmpty == false) ||
                                   !(language ?? "").isEmpty ||
                                   (genre?.isEmpty == false) ||
                                   year != nil ||
                                   badge != nil ||
                                   category == .releaseRadar ||
                                   category == .stalled ||
                                   category == .quickBites ||
                                   !smartRules.isEmpty

        if !needsSwiftRefinement && groupBy == .none {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }

        try Task.checkCancellation()
        var results: [MediaItem] = []
        do {
            results = try modelContext.fetch(descriptor)
        } catch {
            AppLogger.warning("Fetch failed: \(error)", logger: AppLogger.data)
            results = []
        }

        try Task.checkCancellation()
        // 2. Swift-Level Refinement — all filters handled in Swift (cachedGenres is transformable,
        // not safe in #Predicate). buildFilteredPredicate only applies category + search.
        results = try refineResults(results, network: network, language: language, genre: genre, year: year, state: state, badge: badge, searchText: processedSearch, category: category, smartRules: smartRules)

        let totalCount = (needsSwiftRefinement || groupBy != .none) ?
                         results.count :
                         (try? modelContext.fetchCount(FetchDescriptor<MediaItem>(predicate: basePredicate))) ?? results.count

        if needsSwiftRefinement && groupBy == .none {
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

    private func refineResults(_ results: [MediaItem], network: [String]?, language: String?, genre: String?, year: String?, state: MediaState?, badge: String?, searchText: String, category: NavigationCategory? = nil, smartRules: [SmartRule] = []) throws -> [MediaItem] {
        try Task.checkCancellation()
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

        try Task.checkCancellation()

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
            let radarBadges: Set<String> = ["NEW", "BINGE DROP", "PREMIERE", "FINALE"]
            let now = Date()
            refined = refined.filter { item in
                // 1. Must have a valid radar badge
                guard let badge = item.storedSmartBadgeLabel, radarBadges.contains(badge) else { return false }
                
                // 2. Must have already aired/released (Prevents future hype-badges from appearing in the Radar)
                let airDate = item.cachedNextAiringDate ?? item.releaseDate ?? .distantFuture
                return airDate <= now
            }
        }

        try Task.checkCancellation()

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
        
        try Task.checkCancellation()

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

        try Task.checkCancellation()

        if let s = state {
            refined = refined.filter { $0.state == s }
        }

        if !searchText.isEmpty {
            let tokens = searchText.split(separator: " ").map(String.init)
            refined = refined.filter { item in
                let target = item.searchableText
                return tokens.allSatisfy { target.localizedStandardContains($0) }
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

    private func fetchRecentlyAdded(category: NavigationCategory) -> [MediaThumbnailMetadata] {
        if category == .home { return [] }
        var recentDesc = FetchDescriptor<MediaItem>()
        recentDesc.propertiesToFetch = [
            \.id, \.title, \.posterURL, \.backdropURL, \.releaseDate,
            \.typeValue, \.stateValue, \.tasteValue, \.themeColorHex,
            \.lastInteractionDate, \.lastStateChangeDate, \.dateAdded, \.lastUpdated,
            \.cachedGenres, \.cachedCreators, \.cachedLanguage, \.cachedNetwork,
            \.cachedNetworkLogoPath, \.cachedNextAiringDate, \.cachedRuntime,
            \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount, \.remainingEpisodesCount,
            \.storedSmartBadgeLabel, \.storedSmartBadgeIsSparkle, \.storedIsUpcoming,
            \.storedNextEpisodeLabel, \.storedWatchProgressLabel, \.storedProgress,
            \.searchableText
        ]
        recentDesc.sortBy = [
            SortDescriptor<MediaItem>(\.dateAdded, order: .reverse),
            SortDescriptor<MediaItem>(\.title, order: .forward)
        ]
        recentDesc.fetchLimit = 12
        
        if let recentItems = try? modelContext.fetch(recentDesc) {
            return recentItems.map { toMetadata($0) }
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
        let hiddenStudios = UserDefaults.standard.string(forKey: UserDefaultsKeys.hiddenStudios.rawValue) ?? ""
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
        guard let fetchedItem = modelContext.model(for: id) as? MediaItem else { return nil }
        
        if let collectionID = collectionID {
            let collectionDescriptor = FetchDescriptor<MediaCollection>(predicate: #Predicate { $0.id == collectionID })
            if let collection = try? modelContext.fetch(collectionDescriptor).first {
                if collection.isSmart {
                    if !applySmartRules([fetchedItem], rules: collection.smartRules).contains(where: { $0.id == fetchedItem.id }) {
                        return nil
                    }
                } else if !collection.items.contains(where: { $0.id == fetchedItem.id }) {
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
            if fetchedItem.tasteValue != TasteValue.love.rawValue { return nil }
        case .completed:
            if fetchedItem.stateValue != "Completed" { return nil }
        case .archive:
            if fetchedItem.stateValue != "Archive" { return nil }
        case .disliked:
            if fetchedItem.tasteValue != TasteValue.dislike.rawValue { return nil }
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
            if fetchedItem.storedSmartBadgeLabel != "BEHIND" { return nil }
        case .stalled:
            let isStalled = fetchedItem.stateValue == "Active" || fetchedItem.stateValue == "On Hold" || fetchedItem.stateValue == "Dropped"
            if !isStalled { return nil }
        case .smartUpcoming:
            if fetchedItem.storedSmartBadgeLabel != "PREMIERE" { return nil }
        default:
            break
        }
        
        let refined = try refineResults(
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

    func toMetadata(_ item: MediaItem) -> MediaThumbnailMetadata {
        MediaThumbnailMetadata(item: item)
    }
}

// MARK: - Grouping Logic
extension MediaFilterActor {
    func groupResults(_ results: [MediaItem], groupBy: GroupBy, collectionID: UUID? = nil) -> [(String, [MediaThumbnailMetadata])] {
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
}

// MARK: - Sorting Logic
extension MediaFilterActor {
    func sortResults(_ results: inout [MediaItem], category: NavigationCategory, sortOrder: SortOrder) {
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

    func applySortOrder(to descriptor: inout FetchDescriptor<MediaItem>, category: NavigationCategory, sortOrder: SortOrder, badge: String? = nil) {
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
}

// MARK: - Home Category Processing
extension MediaFilterActor {
    func processHomeCategory(now: Date, totalCount: Int) throws -> PaginatedResult {
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
        
        let distantFuture = Date.distantFuture
        let pTransition = #Predicate<MediaItem> { item in
            item.storedIsUpcoming == true && (
                (item.cachedNextAiringDate ?? distantFuture < now) ||
                (item.releaseDate ?? distantFuture < now)
            )
        }
        
        let activeState = "Active"
        let rewatchingState = "Re-watching"
        let pActiveOrRewatching = #Predicate<MediaItem> { item in
            (item.stateValue == activeState || item.stateValue == rewatchingState) &&
            item.tasteValue != dislikeLabel
        }
        
        var descStreaming = FetchDescriptor<MediaItem>(predicate: pStreaming)
        descStreaming.propertiesToFetch = [
            \.id, \.title, \.posterURL, \.backdropURL, \.releaseDate,
            \.typeValue, \.stateValue, \.tasteValue, \.themeColorHex,
            \.lastInteractionDate, \.lastStateChangeDate, \.dateAdded, \.lastUpdated,
            \.cachedGenres, \.cachedCreators, \.cachedLanguage, \.cachedNetwork,
            \.cachedNetworkLogoPath, \.cachedNextAiringDate, \.cachedRuntime,
            \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount, \.remainingEpisodesCount,
            \.storedSmartBadgeLabel, \.storedSmartBadgeIsSparkle, \.storedIsUpcoming,
            \.storedNextEpisodeLabel, \.storedWatchProgressLabel, \.storedProgress,
            \.searchableText, \.storedCast
        ]
        descStreaming.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descStreaming.fetchLimit = 150
        
        var descTransition = FetchDescriptor<MediaItem>(predicate: pTransition)
        descTransition.propertiesToFetch = [
            \.id, \.title, \.posterURL, \.backdropURL, \.releaseDate,
            \.typeValue, \.stateValue, \.tasteValue, \.themeColorHex,
            \.lastInteractionDate, \.lastStateChangeDate, \.dateAdded, \.lastUpdated,
            \.cachedGenres, \.cachedCreators, \.cachedLanguage, \.cachedNetwork,
            \.cachedNetworkLogoPath, \.cachedNextAiringDate, \.cachedRuntime,
            \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount, \.remainingEpisodesCount,
            \.storedSmartBadgeLabel, \.storedSmartBadgeIsSparkle, \.storedIsUpcoming,
            \.storedNextEpisodeLabel, \.storedWatchProgressLabel, \.storedProgress,
            \.searchableText, \.storedCast
        ]
        descTransition.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descTransition.fetchLimit = 50
        
        var descActiveOrRewatching = FetchDescriptor<MediaItem>(predicate: pActiveOrRewatching)
        descActiveOrRewatching.propertiesToFetch = [
            \.id, \.title, \.posterURL, \.backdropURL, \.releaseDate,
            \.typeValue, \.stateValue, \.tasteValue, \.themeColorHex,
            \.lastInteractionDate, \.lastStateChangeDate, \.dateAdded, \.lastUpdated,
            \.cachedGenres, \.cachedCreators, \.cachedLanguage, \.cachedNetwork,
            \.cachedNetworkLogoPath, \.cachedNextAiringDate, \.cachedRuntime,
            \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount, \.remainingEpisodesCount,
            \.storedSmartBadgeLabel, \.storedSmartBadgeIsSparkle, \.storedIsUpcoming,
            \.storedNextEpisodeLabel, \.storedWatchProgressLabel, \.storedProgress,
            \.searchableText, \.storedCast
        ]
        descActiveOrRewatching.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descActiveOrRewatching.fetchLimit = 200
        
        let streamingItems = try modelContext.fetch(descStreaming)
        let transitionItems = try modelContext.fetch(descTransition)
        let activeItemsRaw = try modelContext.fetch(descActiveOrRewatching)
        
        let recentPredicate = #Predicate<MediaItem> { item in
            item.stateValue == "Wishlist" && item.tasteValue != "Dislike"
        }
        var recentDesc = FetchDescriptor<MediaItem>(predicate: recentPredicate)
        recentDesc.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        recentDesc.fetchLimit = 100
        
        let recentItems = try modelContext.fetch(recentDesc)
        
        var homeResultsSet = Set<PersistentIdentifier>()
        var homeResults: [MediaItem] = []
        
        for item in (streamingItems + transitionItems + activeItemsRaw + recentItems) {
            if !homeResultsSet.contains(item.persistentModelID) {
                homeResultsSet.insert(item.persistentModelID)
                homeResults.append(item)
            }
        }
        
        // Use the now parameter passed from filterAndSort
        let activeItems = homeResults.filter { item in
            if item.stateValue == "Completed" || item.stateValue == "Dropped" || item.stateValue == "On Hold" { return false }
            if item.storedIsUpcoming {
                let airDate = item.cachedNextAiringDate ?? .distantFuture
                if airDate > now { return false }
                let daysSinceAir = now.timeIntervalSince(airDate) / 86400
                if daysSinceAir > 14 { return false }
            }
            
            let isCaughtUp = (item.remainingEpisodesCount ?? 0) == 0
            let nextAirDate = item.cachedNextAiringDate ?? .distantPast
            if isCaughtUp && nextAirDate > now && item.type == .tvShow {
                return false
            }
            
            let isCurrentlyWatching = item.stateValue == "Active" || item.stateValue == "Re-watching" || (item.storedProgress ?? 0) > 0
            if isCurrentlyWatching {
                if (item.stateValue == "Active" || item.stateValue == "Re-watching") && (item.storedProgress ?? 0) == 0 {
                    let lastInter = item.lastInteractionDate ?? .distantPast
                    let thirtyDaysAgo = now.addingTimeInterval(-30 * 86400)
                    if lastInter < thirtyDaysAgo {
                        return false
                    }
                }
                return true
            }
            
            let badge = item.storedSmartBadgeLabel
            let isNewDrop = badge == "NEW" || badge == "BINGE DROP" || badge == "FINALE" || badge == "PREMIERE"
            
            if isNewDrop {
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
            
            return itemA.title < itemB.title
        }
        
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
}

private let _filterActorCache = OSAllocatedUnfairLock<MediaFilterActor?>(uncheckedState: nil)

extension MediaFilterActor {
    static func shared(modelContainer: ModelContainer) -> MediaFilterActor {
        _filterActorCache.withLockUnchecked { state in
            if let existing = state {
                return existing
            }
            let actor = MediaFilterActor(modelContainer: modelContainer)
            state = actor
            return actor
        }
    }
}
