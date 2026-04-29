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
        genre: String? = nil,
        groupBy: GroupBy = .none,
        limit: Int = 40,
        offset: Int = 0
    ) throws -> PaginatedResult {

        let now = Date()
        
        // 1. Database-Level Filtering (Predicate)
        // Note: For complex multi-token search, we still do a base fetch and refine in Swift
        // because Predicate containment is limited.
        var basePredicate: Predicate<MediaItem>? = nil
        
        if let category = category {
            switch category {
            case "Upcoming":
                basePredicate = #Predicate<MediaItem> { $0.storedIsUpcoming == true }
            case "InProgress":
                basePredicate = #Predicate<MediaItem> { $0.stateValue == "Active" && $0.storedIsUpcoming == false }
            case "Watchlist":
                basePredicate = #Predicate<MediaItem> { $0.stateValue == "Wishlist" && $0.storedIsUpcoming == false }
            case "Loved":
                basePredicate = #Predicate<MediaItem> { $0.tasteValue == "Love" }
            case "Completed":
                basePredicate = #Predicate<MediaItem> { $0.stateValue == "Completed" }
            case "Archive":
                basePredicate = #Predicate<MediaItem> { $0.stateValue == "On Hold" || $0.stateValue == "Dropped" || $0.stateValue == "Re-watching" }
            case "Disliked":
                basePredicate = #Predicate<MediaItem> { $0.tasteValue == "Dislike" }
            case "Binge":
                basePredicate = #Predicate<MediaItem> { $0.storedIsBingeDrop == true || $0.storedSmartBadgeLabel == "BINGE" }
            default:
                if let type = MediaType(rawValue: category) {
                    let typeString = type.rawValue
                    basePredicate = #Predicate<MediaItem> { $0.typeValue == typeString }
                }
            }
        }
        
        var descriptor = FetchDescriptor<MediaItem>(predicate: basePredicate)
        
        // 2. Database-Level Sorting
        switch sortOrder {
        case .alphabetical: 
            descriptor.sortBy = [SortDescriptor(\.title, order: .forward)]
        case .newestRelease: 
            descriptor.sortBy = [SortDescriptor(\.releaseDate, order: .reverse)]
        case .recentlyAdded: 
            descriptor.sortBy = [SortDescriptor(\.dateAdded, order: .reverse)]
        }
        
        // Phase 5 Optimization: Only apply DB-level pagination if NOT searching or grouping
        // because those operations require full result set analysis.
        if searchText.isEmpty && network?.isEmpty ?? true && language?.isEmpty ?? true && genre == nil && groupBy == .none {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        
        var results = try modelContext.fetch(descriptor)
        
        // 3. Swift-Level Refinement (For Search and Optional Filters)
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

        if let g = genre, !g.isEmpty {
            results = results.filter { $0.cachedGenres.contains(g) }
        }

        let totalCount = (searchText.isEmpty && network?.isEmpty ?? true && language?.isEmpty ?? true && genre == nil) ? 
                         (try? modelContext.fetchCount(FetchDescriptor<MediaItem>(predicate: basePredicate))) ?? results.count : 
                         results.count

        var featuredUpcoming: [MediaThumbnailMetadata] = []
        var homeContinueWatching: [MediaThumbnailMetadata] = []
        
        // 4. Partitioning and Specialized Logic
        if let category = category {
            switch category {
            case "Home":
                // Home view always needs its special logic, but we can optimize the fetch
                let homePredicate = #Predicate<MediaItem> { 
                    $0.stateValue != "Completed" && $0.tasteValue != "Dislike"
                }
                var homeDesc = FetchDescriptor<MediaItem>(predicate: homePredicate)
                homeDesc.sortBy = [SortDescriptor(\.lastInteractionDate, order: .reverse)]
                let homeResults = try modelContext.fetch(homeDesc)
                
                let activeItems = homeResults.filter { item in
                    let airDate = item.cachedNextAiringDate ?? .distantPast
                    let isFuture = airDate > now
                    let isActive = item.stateValue == "Active"
                    let isRecentlyReleased = item.storedSmartBadgeLabel == "STREAMING" || 
                                             (item.storedSmartBadgeLabel == "NEW" && item.typeValue == "Movie") || 
                                             item.storedIsBingeDrop
                                             
                    return (isActive && !isFuture) || isRecentlyReleased
                }
                
                homeContinueWatching = activeItems.prefix(20).map { toMetadata($0) }
                
                let comingSoonItems = homeResults.filter { item in
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
            default:
                break
            }
        }
        
        // Apply pagination in Swift if it wasn't applied at DB level (Search/Filters active)
        var paginatedResults = results
        if !searchText.isEmpty || !(network?.isEmpty ?? true) || !(language?.isEmpty ?? true) || genre != nil || groupBy != .none {
            if offset < results.count {
                let end = min(offset + limit, results.count)
                paginatedResults = Array(results[offset..<end])
            } else {
                paginatedResults = []
            }
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
}
