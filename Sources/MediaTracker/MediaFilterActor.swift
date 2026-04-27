import Foundation
import SwiftData

struct MediaThumbnailMetadata: Sendable, Identifiable {
    let id: PersistentIdentifier
    let title: String
    let posterURL: String?
    let backdropURL: String?
    let overview: String
    let genres: [String]
    let releaseDate: Date?
    let state: MediaState?
    let type: MediaType?
    let taste: String?
    let cachedNextAiringDate: Date?
    let cachedNetwork: String?
    let themeColorHex: String?
    let badgeText: String?
    let watchProgress: String?
    let nextEpisodeToWatchLabel: String?
    let progress: Double?
    let isUpcoming: Bool
    let isBingeDrop: Bool
    let smartBadgeLabel: String?
    let smartBadgeIcon: String?
    let isSparkleBadge: Bool
    let versionHash: Int
    let recommendationReason: String?
    let remainingCount: Int?

    init(item: MediaItem, recommendationReason: String? = nil) {
        self.id = item.persistentModelID
        self.title = item.title
        self.posterURL = item.posterURL
        self.backdropURL = item.backdropURL
        self.overview = item.overview
        self.genres = item.cachedGenres
        self.releaseDate = item.releaseDate
        self.state = item.state
        self.type = item.type
        self.taste = item.tasteValue
        self.cachedNextAiringDate = item.cachedNextAiringDate
        self.cachedNetwork = item.cachedNetwork
        self.themeColorHex = item.themeColorHex
        self.badgeText = item.badgeText
        self.watchProgress = item.storedWatchProgressLabel
        self.nextEpisodeToWatchLabel = item.storedNextEpisodeLabel
        self.progress = item.storedProgress
        self.isUpcoming = item.isUpcoming
        self.isBingeDrop = item.storedIsBingeDrop
        self.smartBadgeLabel = item.storedSmartBadgeLabel
        self.smartBadgeIcon = item.storedSmartBadgeIcon
        self.isSparkleBadge = item.storedSmartBadgeIsSparkle
        self.versionHash = item.lastStateChangeDate.hashValue
        self.remainingCount = item.remainingEpisodesCount
        self.recommendationReason = recommendationReason
    }

    var formattedMetadata: String {
        var parts: [String] = []
        if let releaseDate = releaseDate {
            parts.append(Calendar.current.component(.year, from: releaseDate).description)
        }
        if let type = type {
            parts.append(type == .movie ? "Movie" : "Series")
        }
        if let network = cachedNetwork, !network.isEmpty {
            parts.append(network)
        }
        return parts.joined(separator: " • ")
    }
}

struct PaginatedResult {
    let displayed: [MediaThumbnailMetadata]
    let featuredUpcoming: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let homeContinueWatching: [MediaThumbnailMetadata]
    let grouped: [(String, [MediaThumbnailMetadata])]
    let totalCount: Int
}

@ModelActor
actor MediaFilterActor {
    private func parseAliases() -> [String: Set<String>] {
        let aliasString = UserDefaults.standard.string(forKey: "studio_aliases") ?? ""
        let lines = aliasString.components(separatedBy: .newlines)
        var targetToSources: [String: Set<String>] = [:]
        
        for line in lines where line.contains("=") {
            let parts = line.components(separatedBy: "|")[0].components(separatedBy: "=")
            guard parts.count >= 2 else { continue }
            let target = parts[0].trimmingCharacters(in: .whitespaces)
            let sources = parts[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            targetToSources[target] = Set(sources)
        }
        return targetToSources
    }

    func filterAndSort(
        category: String?,
        searchText: String,
        sortOrder: SortOrder,
        network: [String]?,
        language: String?,
        groupBy: GroupBy = .none,
        limit: Int = 40,
        offset: Int = 0
    ) throws -> PaginatedResult {

        let now = Date()
        // 1. Fetch data with database-level filtering (Category Only to keep Predicate simple)
        var predicate: Predicate<MediaItem>? = nil
        var explicitSort: [SortDescriptor<MediaItem>]? = nil
        
        if let category = category {
            switch category {
            case "Home":
                predicate = #Predicate<MediaItem> { 
                    $0.stateValue != "Completed" && $0.tasteValue != "Dislike"
                }
            case "Upcoming":
                predicate = #Predicate<MediaItem> { $0.storedIsUpcoming == true }
                explicitSort = [SortDescriptor(\.cachedNextAiringDate, order: .forward)]
            case "InProgress":
                predicate = #Predicate<MediaItem> { $0.stateValue == "Active" && $0.storedIsUpcoming == false }
            case "Watchlist":
                predicate = #Predicate<MediaItem> { $0.stateValue == "Wishlist" && $0.storedIsUpcoming == false }
            case "Loved":
                predicate = #Predicate<MediaItem> { $0.tasteValue == "Love" }
            case "Completed":
                predicate = #Predicate<MediaItem> { $0.stateValue == "Completed" }
            case "Archive":
                predicate = #Predicate<MediaItem> { $0.stateValue == "On Hold" || $0.stateValue == "Dropped" || $0.stateValue == "Re-watching" }
            case "Disliked":
                predicate = #Predicate<MediaItem> { $0.tasteValue == "Dislike" }
            case "Binge":
                predicate = #Predicate<MediaItem> { $0.storedIsBingeDrop == true || $0.storedSmartBadgeLabel == "BINGE" }
            case "All":
                predicate = nil
            default:
                if let type = MediaType(rawValue: category) {
                    let typeString = type.rawValue
                    predicate = #Predicate<MediaItem> { $0.typeValue == typeString }
                }
            }
        }
        
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
        
        // 2. Apply Sorting at DB level
        if let explicitSort = explicitSort {
            descriptor.sortBy = explicitSort
        } else {
            switch sortOrder {
            case .alphabetical: descriptor.sortBy = [SortDescriptor(\.title, order: .forward)]
            case .newestRelease: descriptor.sortBy = [SortDescriptor(\.releaseDate, order: .reverse)]
            case .recentlyAdded: descriptor.sortBy = [SortDescriptor(\.dateAdded, order: .reverse)]
            }
        }
        
        var results = try modelContext.fetch(descriptor)
        
        // 3. Fine-grained Swift Filtering (Better for complex multi-token search and optional filters)
        if !searchText.isEmpty {
            let processedSearchText = searchText.lowercased()
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: ":", with: "")
            
            let searchTokens = processedSearchText.split(separator: " ").map(String.init)
            results = results.filter { item in
                let target = item.searchableText
                return searchTokens.allSatisfy { target.contains($0) }
            }
        }
        
        if let nets = network, !nets.isEmpty {
            let normalizedNets = Set(nets.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
            results = results.filter { item in
                guard let itemNet = item.cachedNetwork?.lowercased().trimmingCharacters(in: .whitespaces) else { return false }
                return normalizedNets.contains(itemNet)
            }
        }
        
        if let lang = language, !lang.isEmpty {
            results = results.filter { $0.cachedLanguage == lang }
        }

        let totalCount = results.count
        var featuredUpcoming: [MediaThumbnailMetadata] = []
        var homeContinueWatching: [MediaThumbnailMetadata] = []
        
        // 4. Partitioning and Specialized Logic
        if let category = category {
            switch category {
            case "Home":
                let activeItems = results.filter { item in
                    let airDate = item.cachedNextAiringDate ?? .distantPast
                    let isFuture = airDate > now
                    let isActive = item.stateValue == "Active"
                    
                    // Replace the flawed storedIsUpcoming check with explicit smart badge presence.
                    // If it has a recent drop badge, it's a recent release regardless of Watchlist status.
                    // NEW badge clutters dashboard for TV show premieres, so only allow NEW for movies.
                    let isRecentlyReleased = item.storedSmartBadgeLabel == "STREAMING" || 
                                             (item.storedSmartBadgeLabel == "NEW" && item.typeValue == "Movie") || 
                                             item.storedIsBingeDrop
                                             
                    return (isActive && !isFuture) || isRecentlyReleased
                }.sorted { item1, item2 in
                    // Phase 3 Optimization: Prioritize Smart Badges (STREAMING/BINGE), then Interaction Time
                    let b1 = item1.storedSmartBadgeLabel == "STREAMING" || item1.storedIsBingeDrop
                    let b2 = item2.storedSmartBadgeLabel == "STREAMING" || item2.storedIsBingeDrop
                    
                    if b1 != b2 { return b1 } 
                    
                    let int1 = item1.lastInteractionDate ?? item1.dateAdded
                    let int2 = item2.lastInteractionDate ?? item2.dateAdded
                    return int1 > int2
                }
                
                homeContinueWatching = activeItems.prefix(20).map { toMetadata($0) }
                
                let comingSoonItems = results.filter { item in
                    let airDate = item.cachedNextAiringDate ?? .distantPast
                    return airDate > now
                }.sorted { ($0.cachedNextAiringDate ?? .distantPast) < ($1.cachedNextAiringDate ?? .distantPast) }
                
                return PaginatedResult(
                    displayed: [], 
                    featuredUpcoming: [], 
                    recentlyAdded: [], 
                    homeContinueWatching: homeContinueWatching,
                    grouped: [("Coming Soon", comingSoonItems.map { toMetadata($0) })], 
                    totalCount: totalCount
                )
            case "Upcoming":
                results.sort { ($0.cachedNextAiringDate ?? .distantPast) < ($1.cachedNextAiringDate ?? .distantPast) }
                let tenDaysFromNow = now.addingTimeInterval(86400 * 10)
                let tenDayItems = results.filter { 
                    if let date = $0.cachedNextAiringDate {
                        return date <= tenDaysFromNow && date > now
                    }
                    return false
                }
                if tenDayItems.isEmpty {
                    featuredUpcoming = results.prefix(5).map { toMetadata($0) }
                } else {
                    featuredUpcoming = tenDayItems.map { toMetadata($0) }
                }
            case "InProgress":
                results.sort {
                    if $0.storedIsBingeDrop != $1.storedIsBingeDrop { return $0.storedIsBingeDrop && !$1.storedIsBingeDrop }
                    return ($0.lastUpdated ?? .distantPast) > ($1.lastUpdated ?? .distantPast)
                }
            case "Archive":
                let onHoldItems = results.filter { $0.stateValue == "On Hold" }.map { toMetadata($0) }
                let droppedItems = results.filter { $0.stateValue == "Dropped" }.map { toMetadata($0) }
                let rewatchingItems = results.filter { $0.stateValue == "Re-watching" }.map { toMetadata($0) }
                
                var archiveGroups: [(String, [MediaThumbnailMetadata])] = []
                if !onHoldItems.isEmpty { archiveGroups.append(("On Hold", onHoldItems)) }
                if !droppedItems.isEmpty { archiveGroups.append(("Dropped", droppedItems)) }
                if !rewatchingItems.isEmpty { archiveGroups.append(("Re-watching", rewatchingItems)) }
                
                return PaginatedResult(displayed: [], featuredUpcoming: [], recentlyAdded: [], homeContinueWatching: [], grouped: archiveGroups, totalCount: totalCount)
            case "Binge":
                let bingeDrops = results.filter { $0.storedIsBingeDrop == true }.map { toMetadata($0) }
                let readyToBinge = results.filter { $0.storedSmartBadgeLabel == "BINGE" }.map { toMetadata($0) }
                
                var bingeGroups: [(String, [MediaThumbnailMetadata])] = []
                if !bingeDrops.isEmpty { bingeGroups.append(("Binge Drops", bingeDrops)) }
                if !readyToBinge.isEmpty { bingeGroups.append(("Ready to Binge", readyToBinge)) }
                
                return PaginatedResult(
                    displayed: [], 
                    featuredUpcoming: [], 
                    recentlyAdded: [], 
                    homeContinueWatching: [],
                    grouped: bingeGroups, 
                    totalCount: totalCount
                )
            default:
                break
            }
        }
        
        // Apply pagination in Swift after final filtering
        var paginatedResults = results
        if offset < results.count {
            let end = min(offset + limit, results.count)
            paginatedResults = Array(results[offset..<end])
        } else {
            paginatedResults = []
        }

        // Fetch Recently Added (Limited fetch for efficiency)
        var recentDescriptor = FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
        recentDescriptor.fetchLimit = 5
        let finalRecentlyAdded = try modelContext.fetch(recentDescriptor)
        
        // Helper to convert to lightweight metadata
        func toMetadata(_ item: MediaItem) -> MediaThumbnailMetadata {
            return MediaThumbnailMetadata(item: item)
        }
        var finalGroupedItems: [(String, [MediaThumbnailMetadata])] = []
        if groupBy != .none {
            let dict = Dictionary(grouping: results) { item -> String in
                switch groupBy {
                case .year:
                    if let date = item.releaseDate {
                        return Calendar.current.component(.year, from: date).description
                    }
                    return "Unknown Year"
                case .category:
                    return item.type?.pluralName ?? "Unknown"
                case .none:
                    return ""
                }
            }
            let sortedKeys = dict.keys.sorted { key1, key2 in
                if groupBy == .year {
                    if key1 == "Unknown Year" { return false }
                    if key2 == "Unknown Year" { return true }
                    return key1 > key2
                }
                return key1 < key2
            }
            finalGroupedItems = sortedKeys.map { ( $0, dict[$0]!.map { toMetadata($0) } ) }
        }
        
        return PaginatedResult(
            displayed: paginatedResults.map { toMetadata($0) },
            featuredUpcoming: featuredUpcoming,
            recentlyAdded: finalRecentlyAdded.map { toMetadata($0) },
            homeContinueWatching: homeContinueWatching,
            grouped: finalGroupedItems,
            totalCount: totalCount
        )
    }

    func calculateDiscoveryNodes(hiddenStudios: String) throws -> (networks: [DiscoveryNode], genres: [DiscoveryNode], languages: [DiscoveryNode], hash: Int) {
        let networkEntities = try modelContext.fetch(FetchDescriptor<NetworkEntity>())
        let genreEntities = try modelContext.fetch(FetchDescriptor<GenreEntity>())
        let languageEntities = try modelContext.fetch(FetchDescriptor<LanguageEntity>())
        let hiddenSet = Set(hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty })
        
        let networks: [DiscoveryNode] = networkEntities.compactMap { entity in
            guard !hiddenSet.contains(entity.name) else { return nil }
            return DiscoveryNode(name: entity.name, logoPath: entity.logoPath, count: entity.count, themeColorHex: entity.themeColorHex, sourceNames: entity.sourceNames)
        }.sorted { 
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let genres: [DiscoveryNode] = genreEntities.map { DiscoveryNode(name: $0.name, logoPath: nil, count: $0.count) }.sorted { 
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let languages: [DiscoveryNode] = languageEntities.map { DiscoveryNode(name: $0.code, logoPath: nil, count: $0.count) }.sorted { 
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let currentLibraryHash = networks.count ^ genres.count ^ languages.count
        return (networks, genres, languages, currentLibraryHash)
    }
}
