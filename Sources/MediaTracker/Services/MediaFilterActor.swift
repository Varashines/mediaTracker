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
        provider: String? = nil,
        groupBy: GroupBy = .none,
        collectionID: UUID? = nil,
        limit: Int = 40,
        offset: Int = 0
    ) async throws -> PaginatedResult {

        let now = Date()
        let processedSearch = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let searchToken = processedSearch.split(separator: " ").first.map(String.init) ?? ""
        // Pre-compute filter values for Swift-level refinement
        let stateRaw = state?.rawValue

        // Home category uses its own queries — skip the general fetch entirely
        if category == .home {
            return try await processHomeCategory(now: now, totalCount: 0)
        }

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
                                   (genre?.isEmpty == false) ||
                                   year != nil ||
                                   provider != nil ||
                                   category == .releaseRadar ||
                                   category == .quickBites ||
                                   !smartRules.isEmpty ||
                                   !processedSearch.isEmpty

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
        results = try refineResults(results, network: network, language: language, genre: genre, year: year, state: state, badge: badge, provider: provider, searchText: processedSearch, category: category, smartRules: smartRules)

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
        if category == .upcoming && collectionID == nil {
            featuredUpcoming = results.prefix(15).map { toMetadata($0) }
            results = Array(results.dropFirst(results.count > 15 ? 15 : 0))
        }

        // 4. Grouping Logic
        let finalGroupedItems = groupResults(results, groupBy: groupBy, collectionID: collectionID)

        // 5. Fetch Recently Added (skip for home — it uses its own queries)
        let recentAddedItems: [MediaThumbnailMetadata]
        if category == .home {
            recentAddedItems = []
        } else {
            recentAddedItems = fetchRecentlyAdded(category: category)
        }

        return PaginatedResult(
            displayed: results.map { toMetadata($0) },
            featuredUpcoming: featuredUpcoming,
            recentlyAdded: recentAddedItems,
            homeContinueWatching: [],
            spotlightHero: nil,
            grouped: finalGroupedItems,
            pickOfTheDay: [],
            recommendations: [],
            totalCount: totalCount
        )
    }

    private func refineResults(_ results: [MediaItem], network: [String]?, language: String?, genre: String?, year: String?, state: MediaState?, badge: String?, provider: String? = nil, searchText: String, category: NavigationCategory? = nil, smartRules: [SmartRule] = []) throws -> [MediaItem] {
        try Task.checkCancellation()
        let normalizedNets = network.map { Set($0.map { $0.lowercased() }) }
        let searchTokens = searchText.isEmpty ? nil : searchText.split(separator: " ").map(String.init)
        let now = Date()
        let radarBadges: Set<String> = ["NEW", "BINGE DROP", "PREMIERE", "FINALE"]
        let calendar = Calendar.current

        func passesNonSearchFilters(_ item: MediaItem) -> Bool {
            if !smartRules.isEmpty {
                guard applySmartRule(item, rules: smartRules) else { return false }
            }

            if category == .quickBites {
                if item.typeValue == "Movie" {
                    let runtime = item.cachedRuntime ?? 0
                    guard runtime > 0 && runtime < 90 else { return false }
                } else if item.typeValue == "TV Show" {
                    let epRuntime = item.cachedEpisodeRuntime ?? 0
                    guard epRuntime > 0 && epRuntime < 25 else { return false }
                } else {
                    return false
                }
            }

            if category == .releaseRadar {
                guard let b = item.storedSmartBadgeLabel, radarBadges.contains(b) else { return false }
                let airDate = item.cachedNextAiringDate ?? item.releaseDate ?? .distantFuture
                guard airDate <= now else { return false }
            }

            if let b = badge {
                guard item.storedSmartBadgeLabel == b else { return false }
            }

            if let nets = normalizedNets {
                guard let rawNets = item.cachedNetwork else { return false }
                let itemNets = rawNets.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard itemNets.contains(where: { nets.contains($0.lowercased()) }) else { return false }
            }

            if let lang = language, !lang.isEmpty {
                guard item.cachedLanguage == lang else { return false }
            }

            if let g = genre, !g.isEmpty {
                guard item.cachedGenres.contains(g) else { return false }
            }

            if let p = provider, !p.isEmpty {
                guard item.cachedWatchProviders.contains(p) else { return false }
            }

            if let y = year, !y.isEmpty {
                guard let date = item.releaseDate else { return false }
                let itemYear = calendar.component(.year, from: date)
                guard String(itemYear) == y else { return false }
            }

            if let s = state {
                guard item.state == s else { return false }
            }

            return true
        }

        // Step 1: Apply non-search filters
        let nonSearchFiltered = results.filter { passesNonSearchFilters($0) }

        // Step 2: Apply search filter with scoring
        guard let tokens = searchTokens, !tokens.isEmpty else {
            return nonSearchFiltered
        }

        let scorer = SearchScorer(tokens: tokens)

        // Try AND mode first
        var scored = nonSearchFiltered.compactMap { item -> (MediaItem, Int)? in
            let s = scorer.score(item: item)
            guard scorer.passesAllTokens(item: item) else { return nil }
            return (item, s)
        }

        // Fall back to OR mode if AND produced nothing and query has multiple tokens
        if scored.isEmpty, tokens.count > 1 {
            scored = nonSearchFiltered.compactMap { item -> (MediaItem, Int)? in
                let s = scorer.score(item: item)
                guard s > 0 else { return nil }
                return (item, s)
            }
        }

        // Sort by score descending
        scored.sort { $0.1 > $1.1 }
        return scored.map(\.0)
    }

    private func applySmartRule(_ item: MediaItem, rules: [SmartRule]) -> Bool {
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

    private func applySmartRules(_ items: [MediaItem], rules: [SmartRule]) -> [MediaItem] {
        items.filter { applySmartRule($0, rules: rules) }
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
            return #Predicate { $0.stateValue == "On Hold" || $0.stateValue == "Dropped" }
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
        let studios: [DiscoveryNode]
        let genres: [DiscoveryNode]
        let languages: [DiscoveryNode]
        let providers: [DiscoveryNode]
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
        let hiddenSet = MediaFilterPredicates.hiddenStudiosSet()
        let filteredNets = nets.filter { !hiddenSet.contains($0.name.lowercased()) && $0.count >= 4 }

        let snNetworks = filteredNets
            .filter { $0.kind == "network" || $0.kind.isEmpty }
            .map { DiscoveryNode(name: $0.name, logoPath: $0.logoPath, count: $0.count, themeColorHex: $0.themeColorHex, sourceNames: $0.sourceNames) }
        let snStudios = filteredNets
            .filter { $0.kind == "studio" }
            .map { DiscoveryNode(name: $0.name, logoPath: $0.logoPath, count: $0.count, themeColorHex: $0.themeColorHex, sourceNames: $0.sourceNames) }

        let providerDescriptor = FetchDescriptor<ProviderEntity>(sortBy: [
            SortDescriptor(\.count, order: .reverse),
            SortDescriptor(\.name, order: .forward)
        ])
        let providerEntities = (try? modelContext.fetch(providerDescriptor)) ?? []

        let genres = (try? modelContext.fetch(genreDescriptor)) ?? []
        let langs = (try? modelContext.fetch(langDescriptor)) ?? []

        return LibraryMetadata(
            networks: snNetworks,
            studios: snStudios,
            genres: genres.map { DiscoveryNode(name: $0.name, logoPath: nil, count: $0.count) },
            languages: langs.map { DiscoveryNode(name: LanguageUtils.languageName(for: $0.code), code: $0.code, logoPath: nil, count: $0.count) },
            providers: providerEntities.filter { $0.count >= 1 }.map { DiscoveryNode(name: $0.name, logoPath: $0.logoPath, count: $0.count) }
        )
    }

    func fetchDistinctYears() async -> [String] {
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.releaseDate != nil },
            sortBy: [SortDescriptor(\.releaseDate, order: .reverse)]
        )
        descriptor.propertiesToFetch = [\.releaseDate]
        descriptor.fetchLimit = 2000
        let items = (try? modelContext.fetch(descriptor)) ?? []
        let years = Set(items.compactMap { $0.releaseDate.flatMap { Calendar.current.component(.year, from: $0) } })
        return years.sorted(by: >).map(String.init)
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
        provider: String? = nil,
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
            if fetchedItem.stateValue != "On Hold" && fetchedItem.stateValue != "Dropped" { return nil }
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
            provider: provider,
            searchText: searchText,
            category: category
        )
        
        guard let matchingItem = refined.first else { return nil }
        return toMetadata(matchingItem)
    }

    func toMetadata(_ item: MediaItem) -> MediaThumbnailMetadata {
        MediaThumbnailMetadata(item: item)
    }
    func countItems(category: NavigationCategory, collectionID: UUID? = nil) async throws -> Int {
        let basePredicate = MediaFilterPredicates.buildFilteredPredicate(
            category: category, searchToken: "", stateValue: nil, badge: nil, language: nil
        )
        if let cid = collectionID {
            let colDescriptor = FetchDescriptor<MediaCollection>(predicate: #Predicate { $0.id == cid })
            if let collection = try? modelContext.fetch(colDescriptor).first {
                if collection.isSmart && !collection.smartRules.isEmpty {
                    // Smart rules require Swift-level evaluation — fetch minimal data and count
                    var desc = FetchDescriptor<MediaItem>(predicate: basePredicate)
                    desc.propertiesToFetch = [\.persistentModelID]
                    desc.fetchLimit = 2000
                    let items = try modelContext.fetch(desc)
                    let refined = try refineResults(items, network: nil, language: nil, genre: nil, year: nil, state: nil, badge: nil, provider: nil, searchText: "", smartRules: collection.smartRules)
                    return refined.count
                }
                let itemIDs = collection.items.compactMap { $0.id }
                if itemIDs.isEmpty { return 0 }
                let pred = MediaFilterPredicates.buildManualCollectionPredicate(itemIDs: itemIDs, stateValue: nil)
                return try modelContext.fetchCount(FetchDescriptor<MediaItem>(predicate: pred))
            }
            return 0
        }
        return try modelContext.fetchCount(FetchDescriptor<MediaItem>(predicate: basePredicate))
    }

}

private struct CachedFilterActor {
    let containerID: ObjectIdentifier
    let actor: MediaFilterActor
}

private let _filterActorCache = OSAllocatedUnfairLock<CachedFilterActor?>(uncheckedState: nil)

extension MediaFilterActor {
    static func shared(modelContainer: ModelContainer) -> MediaFilterActor {
        let containerID = ObjectIdentifier(modelContainer)
        return _filterActorCache.withLockUnchecked { state in
            if let cached = state, cached.containerID == containerID {
                return cached.actor
            }
            let actor = MediaFilterActor(modelContainer: modelContainer)
            state = CachedFilterActor(containerID: containerID, actor: actor)
            return actor
        }
    }
}
