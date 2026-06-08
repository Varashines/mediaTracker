import Foundation
import SwiftData
import os

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
        descriptor.propertiesToFetch = MediaItem.thumbnailProperties
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
        } else {
            descriptor.fetchLimit = 2000
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
            let ninetyDaysAgo = Date().addingTimeInterval(-.days90)
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
            let normalizedNets = Set(nets.map { $0.lowercased() })
            refined = refined.filter { item in
                guard let rawNets = item.cachedNetwork else { return false }
                return rawNets.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains { normalizedNets.contains($0.lowercased()) }
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
                case .network(let network):
                    guard let rawNets = item.cachedNetwork else { return false }
                    return rawNets.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.contains(network.lowercased())
                case .language(let language):
                    return item.cachedLanguage?.lowercased() == language.lowercased()
                }
            }
        }
    }

    private func fetchRecentlyAdded(category: NavigationCategory) -> [MediaThumbnailMetadata] {
        if category == .home { return [] }
        var recentDesc = FetchDescriptor<MediaItem>()
        recentDesc.propertiesToFetch = MediaItem.thumbnailProperties
        recentDesc.sortBy = [
            SortDescriptor<MediaItem>(\.dateAdded, order: .reverse),
            SortDescriptor<MediaItem>(\.title, order: .forward)
        ]
        recentDesc.fetchLimit = 12
        
        // Apply category-specific filter so Recently Added respects the current view scope
        if let categoryPredicate = categoryFilterPredicate(category: category) {
            recentDesc.predicate = categoryPredicate
        }
        
        if let recentItems = try? modelContext.fetch(recentDesc) {
            return recentItems.map { toMetadata($0) }
        }
        return []
    }
    
    private func categoryFilterPredicate(category: NavigationCategory) -> Predicate<MediaItem>? {
        switch category {
        case .movie:
            return #Predicate { $0.typeValue == "Movie" }
        case .tvShow:
            return #Predicate { $0.typeValue == "TV Show" }
        case .completed:
            return #Predicate { $0.stateValue == "Completed" }
        case .inProgress:
            return #Predicate { $0.stateValue == "Active" && $0.storedIsUpcoming == false }
        case .watchlist:
            return #Predicate { $0.stateValue == "Wishlist" && $0.storedIsUpcoming == false }
        case .loved:
            return #Predicate { $0.tasteValue == "Love" }
        case .disliked:
            return #Predicate { $0.tasteValue == "Dislike" }
        case .archive:
            return #Predicate { $0.stateValue == "On Hold" || $0.stateValue == "Dropped" || $0.stateValue == "Re-watching" }
        default:
            return nil
        }
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
