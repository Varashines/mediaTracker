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
    let taste: String
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

    var formattedMetadata: String {        var parts: [String] = []
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

struct PaginatedResult: Sendable {
    let displayed: [MediaThumbnailMetadata]
    let featuredUpcoming: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let homeContinueWatching: [MediaThumbnailMetadata]
    let grouped: [(String, [MediaThumbnailMetadata])]
    let totalCount: Int
}

@ModelActor
actor MediaFilterActor {
    func fetchIdentifiers(
        category: String?,
        searchText: String,
        sortOrder: SortOrder,
        network: String?,
        language: String?
    ) throws -> [PersistentIdentifier] {
        var predicate: Predicate<MediaItem>? = nil
        var explicitSort: [SortDescriptor<MediaItem>]? = nil
        
        if let category = category {
            switch category {
            case "Home":
                predicate = #Predicate<MediaItem> {
                    $0.stateValue == "Active" || $0.stateValue == "Re-watching" || $0.storedIsUpcoming == true
                }
            case "Upcoming": 
                predicate = #Predicate<MediaItem> { $0.storedIsUpcoming == true }
                explicitSort = [SortDescriptor(\.cachedNextAiringDate, order: .forward)]
            case "NowWatching": predicate = #Predicate<MediaItem> { $0.stateValue == "Active" && $0.storedIsUpcoming == false }
            case "InProgress": predicate = #Predicate<MediaItem> { ($0.stateValue == "Active" || $0.stateValue == "Re-watching") && $0.storedIsUpcoming == false }
            case "Watchlist": predicate = #Predicate<MediaItem> { $0.stateValue == "Wishlist" && $0.storedIsUpcoming == false }
            case "Loved": predicate = #Predicate<MediaItem> { $0.tasteValue == "Love" }
            case "Completed": predicate = #Predicate<MediaItem> { $0.stateValue == "Completed" }
            case "Archive": predicate = #Predicate<MediaItem> { $0.stateValue == "On Hold" || $0.stateValue == "Dropped" || $0.stateValue == "Re-watching" }
            case "Disliked": predicate = #Predicate<MediaItem> { $0.tasteValue == "Dislike" }
            case "OnHold": predicate = #Predicate<MediaItem> { $0.stateValue == "On Hold" }
            case "Dropped": predicate = #Predicate<MediaItem> { $0.stateValue == "Dropped" }
            case "Rewatching": predicate = #Predicate<MediaItem> { $0.stateValue == "Re-watching" }
            case "All": predicate = nil
            default:
                if let type = MediaType(rawValue: category) {
                    let typeString = type.rawValue
                    predicate = #Predicate<MediaItem> { $0.typeValue == typeString }
                }
            }
        }
        
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
        
        if let explicitSort = explicitSort {
            descriptor.sortBy = explicitSort
        } else {
            switch sortOrder {
            case .alphabetical: descriptor.sortBy = [SortDescriptor(\.title, order: .forward)]
            case .newestRelease: descriptor.sortBy = [SortDescriptor(\.releaseDate, order: .reverse)]
            case .recentlyAdded: descriptor.sortBy = [SortDescriptor(\.dateAdded, order: .reverse)]
            }
        }
        
        // This is a specialized optimization for 8GB M1 Macs:
        // We only fetch the unique identifiers to keep RAM residency low.
        let items = try modelContext.fetch(descriptor)
        
        var filtered = items
        if !searchText.isEmpty {
            let processed = searchText.lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: ":", with: "")
            let tokens = processed.split(separator: " ").map(String.init)
            filtered = items.filter { item in
                let target = item.searchableText
                return tokens.allSatisfy { target.contains($0) }
            }
        }
        
        if let net = network, !net.isEmpty { filtered = filtered.filter { $0.cachedNetwork == net } }
        if let lang = language, !lang.isEmpty { filtered = filtered.filter { $0.cachedLanguage == lang } }
        
        return filtered.map { $0.persistentModelID }
    }

    func filterAndSort(
        category: String?,
        searchText: String,
        sortOrder: SortOrder,
        network: String?,
        language: String?,
        groupBy: GroupBy,
        limit: Int? = nil,
        offset: Int? = nil
    ) throws -> PaginatedResult {
        // 1. Fetch data with minimal database-level filtering
        var predicate: Predicate<MediaItem>? = nil
        var explicitSort: [SortDescriptor<MediaItem>]? = nil
        
        if let category = category {
            switch category {
            case "Home":
                predicate = #Predicate<MediaItem> {
                    $0.stateValue == "Active" || $0.stateValue == "Re-watching" || $0.storedIsUpcoming == true
                }
            case "Upcoming":
                predicate = #Predicate<MediaItem> { $0.storedIsUpcoming == true }
                explicitSort = [SortDescriptor(\.cachedNextAiringDate, order: .forward)]
            case "InProgress":
                predicate = #Predicate<MediaItem> { ($0.stateValue == "Active" || $0.stateValue == "Re-watching") && $0.storedIsUpcoming == false }
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
        
        // Fetch total count before applying limit/offset
        let totalCount = (try? modelContext.fetchCount(descriptor)) ?? 0

        if let limit = limit { descriptor.fetchLimit = limit }
        if let offset = offset { descriptor.fetchOffset = offset }
        
        var results = try modelContext.fetch(descriptor)
        var featuredUpcoming: [MediaThumbnailMetadata] = []
        var homeContinueWatching: [MediaThumbnailMetadata] = []
        
        // 3. Fine-grained Swift Filtering for remaining logic
        if let category = category {
            switch category {
            case "Home":
                let now = Date()
                // Partition 1: Continue Watching (Available right now)
                let activeItems = results.filter { item in
                    let airDate = item.cachedNextAiringDate ?? .distantPast
                    let isFuture = airDate > now
                    
                    let isActive = item.stateValue == "Active" || item.stateValue == "Re-watching"
                    let isRecentlyReleased = item.storedIsUpcoming && airDate <= now
                    
                    // Show if it's active AND has available content (not waiting on future air date),
                    // OR if it's a recently released upcoming item.
                    return (isActive && !isFuture) || isRecentlyReleased
                }.sorted { item1, item2 in
                    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
                    
                    let date1 = item1.cachedNextAiringDate ?? .distantPast
                    let date2 = item2.cachedNextAiringDate ?? .distantPast
                    
                    let isFresh1 = date1 >= thirtyDaysAgo && date1 <= now
                    let isFresh2 = date2 >= thirtyDaysAgo && date2 <= now
                    
                    if isFresh1 && isFresh2 {
                        return date1 > date2 // Both fresh, newer air date first
                    } else if isFresh1 {
                        return true // Only item1 is fresh, it wins
                    } else if isFresh2 {
                        return false // Only item2 is fresh, it wins
                    }
                    
                    // Neither is fresh (or they are both in the distant past), use interaction date
                    let int1 = item1.lastInteractionDate ?? .distantPast
                    let int2 = item2.lastInteractionDate ?? .distantPast
                    return int1 > int2
                }
                
                homeContinueWatching = activeItems.prefix(20).map { toMetadata($0) }
                
                // Partition 2: Coming Soon (Strictly in the future)
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
                featuredUpcoming = results.prefix(5).map { toMetadata($0) }
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
                
                return PaginatedResult(
                    displayed: [], 
                    featuredUpcoming: [], 
                    recentlyAdded: [], 
                    homeContinueWatching: [],
                    grouped: archiveGroups, 
                    totalCount: totalCount
                )
            default:
                break
            }
        }
        
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
        
        if let net = network, !net.isEmpty {
            results = results.filter { $0.cachedNetwork == net }
        }
        
        if let lang = language, !lang.isEmpty {
            results = results.filter { $0.cachedLanguage == lang }
        }
        
        let finalResults = results
        
        // Fetch Recently Added (Limited fetch for efficiency)
        var recentDescriptor = FetchDescriptor<MediaItem>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 5
        let finalRecentlyAdded = try modelContext.fetch(recentDescriptor)
        
        // Helper to convert to lightweight metadata
        func toMetadata(_ item: MediaItem) -> MediaThumbnailMetadata {
            return MediaThumbnailMetadata(
                id: item.persistentModelID,
                title: item.title,
                posterURL: item.posterURL,
                backdropURL: item.backdropURL,
                overview: item.overview,
                genres: item.cachedGenres,
                releaseDate: item.releaseDate,
                state: item.state,
                type: item.type,
                taste: item.tasteValue,
                cachedNextAiringDate: item.cachedNextAiringDate,
                cachedNetwork: item.cachedNetwork,
                themeColorHex: item.themeColorHex,
                badgeText: item.badgeText,
                watchProgress: item.storedWatchProgressLabel,
                nextEpisodeToWatchLabel: item.storedNextEpisodeLabel,
                progress: item.storedProgress,
                isUpcoming: item.storedIsUpcoming,
                isBingeDrop: item.storedIsBingeDrop,
                smartBadgeLabel: item.storedSmartBadgeLabel,
                smartBadgeIcon: item.storedSmartBadgeIcon,
                isSparkleBadge: item.storedSmartBadgeIsSparkle,
                versionHash: item.lastStateChangeDate.hashValue,
                recommendationReason: nil
            )
        }

        var finalGroupedItems: [(String, [MediaThumbnailMetadata])] = []
        if groupBy != .none {
            let dict = Dictionary(grouping: finalResults) { item -> String in
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
            
            finalGroupedItems = sortedKeys.map { key in
                (key, dict[key]!.map { toMetadata($0) })
            }
        }
        
        return PaginatedResult(
            displayed: finalResults.map { toMetadata($0) },
            featuredUpcoming: featuredUpcoming,
            recentlyAdded: finalRecentlyAdded.map { toMetadata($0) },
            homeContinueWatching: homeContinueWatching,
            grouped: finalGroupedItems,
            totalCount: totalCount
        )
    }

    func calculateDiscoveryNodes(hiddenStudios: String) throws -> (networks: [DiscoveryNode], genres: [DiscoveryNode], languages: [DiscoveryNode], hash: Int) {
        // 1. Fetch denormalized discovery entities
        let networkEntities = try modelContext.fetch(FetchDescriptor<NetworkEntity>())
        let genreEntities = try modelContext.fetch(FetchDescriptor<GenreEntity>())
        let languageEntities = try modelContext.fetch(FetchDescriptor<LanguageEntity>())
        
        let hiddenSet = Set(hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty })
        
        let networks: [DiscoveryNode] = networkEntities.compactMap { entity in
            guard !hiddenSet.contains(entity.name) else { return nil }
            return DiscoveryNode(name: entity.name, logoPath: entity.logoPath, count: entity.count, themeColorHex: entity.themeColorHex)
        }.sorted { 
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        
        let genres: [DiscoveryNode] = genreEntities.map { entity in
            DiscoveryNode(name: entity.name, logoPath: nil, count: entity.count)
        }.sorted { 
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
            
        let languages: [DiscoveryNode] = languageEntities.map { entity in
            DiscoveryNode(name: entity.code, logoPath: nil, count: entity.count)
        }.sorted { 
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        
        // Generate a simple hash for cache busting
        let currentLibraryHash = networks.count ^ genres.count ^ languages.count
            
        return (networks, genres, languages, currentLibraryHash)
    }
}
