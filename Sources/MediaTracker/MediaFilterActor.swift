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
    let remainingCount: Int?

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
                    $0.stateValue != "Completed" && 
                    $0.stateValue != "On Hold" && 
                    $0.stateValue != "Dropped" &&
                    $0.tasteValue != "Dislike"
                }
            case "Upcoming": 
                predicate = #Predicate<MediaItem> { $0.storedIsUpcoming == true }
                explicitSort = [SortDescriptor(\.cachedNextAiringDate, order: .forward)]
            case "Loved": predicate = #Predicate<MediaItem> { $0.tasteValue == "Love" }
            case "Completed": predicate = #Predicate<MediaItem> { $0.stateValue == "Completed" }
            case "Archive": predicate = #Predicate<MediaItem> { $0.stateValue == "On Hold" || $0.stateValue == "Dropped" || $0.stateValue == "Re-watching" }
            case "Disliked": predicate = #Predicate<MediaItem> { $0.tasteValue == "Dislike" }
            case "Binge": 
                predicate = #Predicate<MediaItem> { $0.storedIsBingeDrop == true || $0.storedSmartBadgeLabel == "BINGE" }
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
        let now = Date()
        // 1. Fetch data with database-level filtering (Category Only to keep Predicate simple)
        var predicate: Predicate<MediaItem>? = nil
        var explicitSort: [SortDescriptor<MediaItem>]? = nil
        
        if let category = category {
            switch category {
            case "Home":
                predicate = #Predicate<MediaItem> { 
                    $0.stateValue != "Completed" && 
                    $0.stateValue != "On Hold" && 
                    $0.stateValue != "Dropped" &&
                    $0.tasteValue != "Dislike"
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
        
        if let net = network, !net.isEmpty {
            results = results.filter { $0.cachedNetwork == net }
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
                let now = Date()
                let activeItems = results.filter { item in
                    let airDate = item.cachedNextAiringDate ?? .distantPast
                    let isFuture = airDate > now
                    let isActive = item.stateValue == "Active" || item.stateValue == "Re-watching"
                    
                    // Replace the flawed storedIsUpcoming check with explicit smart badge presence.
                    // If it has a recent drop badge, it's a recent release regardless of Watchlist status.
                    // NEW badge clutters dashboard for TV show premieres, so only allow NEW for movies.
                    let isRecentlyReleased = item.storedSmartBadgeLabel == "STREAMING" || 
                                             (item.storedSmartBadgeLabel == "NEW" && item.typeValue == "Movie") || 
                                             item.storedIsBingeDrop
                                             
                    return (isActive && !isFuture) || isRecentlyReleased
                }.sorted { item1, item2 in
                    let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
                    let date1 = item1.cachedNextAiringDate ?? .distantPast
                    let date2 = item2.cachedNextAiringDate ?? .distantPast
                    let isFresh1 = date1 >= thirtyDaysAgo && date1 <= now
                    let isFresh2 = date2 >= thirtyDaysAgo && date2 <= now
                    if isFresh1 && isFresh2 { return date1 > date2 } 
                    else if isFresh1 { return true } 
                    else if isFresh2 { return false }
                    let int1 = item1.lastInteractionDate ?? .distantPast
                    let int2 = item2.lastInteractionDate ?? .distantPast
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
        if let offset = offset, let limit = limit {
            if offset < results.count {
                let end = min(offset + limit, results.count)
                paginatedResults = Array(results[offset..<end])
            } else {
                paginatedResults = []
            }
        } else if let limit = limit {
            paginatedResults = Array(results.prefix(limit))
        }

        // Fetch Recently Added (Limited fetch for efficiency)
        var recentDescriptor = FetchDescriptor<MediaItem>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)])
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
                isUpcoming: item.isUpcoming,
                isBingeDrop: item.storedIsBingeDrop,
                smartBadgeLabel: item.storedSmartBadgeLabel,
                smartBadgeIcon: item.storedSmartBadgeIcon,
                isSparkleBadge: item.storedSmartBadgeIsSparkle,
                versionHash: item.lastStateChangeDate.hashValue,
                recommendationReason: nil,
                remainingCount: item.remainingEpisodesCount
                )
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
            return DiscoveryNode(name: entity.name, logoPath: entity.logoPath, count: entity.count, themeColorHex: entity.themeColorHex)
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
