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
        self.genres = item.cachedGenres
        self.recommendationReason = recommendationReason
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

struct CalendarReleaseItem: Sendable, Identifiable {
    var id: PersistentIdentifier { metadata.id }
    let metadata: MediaThumbnailMetadata
    let releaseContext: String
    let date: Date
}

struct CalendarDayInfo: Sendable, Identifiable {
    var id: Date { date }
    let date: Date
    let items: [CalendarReleaseItem]
    let intensity: Double // 0.0 to 1.0
}

struct CalendarResult: Sendable {
    let days: [Date: CalendarDayInfo]
    let allItems: [CalendarReleaseItem]
    let startDate: Date
    let endDate: Date
}

@ModelActor
actor MediaFilterActor {
    func fetchCalendarData(for month: Date) throws -> CalendarResult {
        let calendar = Calendar.current
        
        // Calculate month bounds
        let components = calendar.dateComponents([.year, .month], from: month)
        guard let startDate = calendar.date(from: components),
              let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) else {
            return CalendarResult(days: [:], allItems: [], startDate: month, endDate: month)
        }
        
        let startOfDay = calendar.startOfDay(for: startDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))?.addingTimeInterval(-1) ?? endDate
        
        let fallbackPast = Date.distantPast
        let fallbackFuture = Date.distantFuture

        // 1. Fetch Movies with air dates in range
        let moviePredicate = #Predicate<MediaItem> { item in
            item.typeValue == "Movie" && item.cachedNextAiringDate != nil &&
            (item.cachedNextAiringDate ?? fallbackPast) >= startOfDay && (item.cachedNextAiringDate ?? fallbackFuture) <= endOfDay
        }
        let movieDesc = FetchDescriptor<MediaItem>(predicate: moviePredicate)
        var movies = try modelContext.fetch(movieDesc)

        // Add fallback for unindexed movies (where cachedNextAiringDate is nil but releaseDate is in range)
        let unindexedMoviePredicate = #Predicate<MediaItem> { item in
            item.typeValue == "Movie" && item.cachedNextAiringDate == nil
        }
        let unindexedMovies = (try? modelContext.fetch(FetchDescriptor<MediaItem>(predicate: unindexedMoviePredicate))) ?? []
        if !unindexedMovies.isEmpty {
            let matchedMovies = unindexedMovies.filter { movie in
                guard let date = movie.releaseDate else { return false }
                return date >= startOfDay && date <= endOfDay
            }
            movies.append(contentsOf: matchedMovies)
        }

        // 2. Fetch TV Episodes in range using persistent airDateValue
        let episodePredicate = #Predicate<TVEpisode> { ep in
            ep.airDateValue != nil && (ep.airDateValue ?? fallbackPast) >= startOfDay && (ep.airDateValue ?? fallbackFuture) <= endOfDay
        }
        let epDesc = FetchDescriptor<TVEpisode>(predicate: episodePredicate)
        var episodesInRange = try modelContext.fetch(epDesc)
        
        // 3. Fallback for unindexed episodes
        // If we found nothing but have unindexed episodes, perform an in-memory scan for this range.
        let unindexedPredicate = #Predicate<TVEpisode> { ep in ep.airDateValue == nil }
        let unindexedEpisodes = (try? modelContext.fetch(FetchDescriptor<TVEpisode>(predicate: unindexedPredicate))) ?? []
        
        if !unindexedEpisodes.isEmpty {
            let matchedUnindexed = unindexedEpisodes.filter { ep in
                guard let date = ep.airDateAsDate else { return false }
                return date >= startOfDay && date <= endOfDay
            }
            if !matchedUnindexed.isEmpty {
                episodesInRange.append(contentsOf: matchedUnindexed)
            }
            
            // Trigger background heal to fix these for next time
            Task.detached(priority: .background) {
                await self.healMissingDates()
            }
        }
        
        // 4. Process and Group
        var dailyItems: [Date: [CalendarReleaseItem]] = [:]
        var allProcessedItems: [CalendarReleaseItem] = []
        
        // Add Movies
        for movie in movies {
            let date = movie.cachedNextAiringDate ?? movie.releaseDate ?? .distantPast
            if date != .distantPast {
                let day = calendar.startOfDay(for: date)
                let item = CalendarReleaseItem(
                    metadata: toMetadata(movie),
                    releaseContext: "Movie Premiere",
                    date: date
                )
                dailyItems[day, default: []].append(item)
                allProcessedItems.append(item)
            }
        }
        
        // Group TV Episodes by Day and Show
        let groupedByDayAndShow = Dictionary(grouping: episodesInRange) { ep -> String in
            let day = calendar.startOfDay(for: ep.airDateAsDate ?? .distantPast)
            let showID = ep.season?.tvShowDetails?.item?.id ?? (ep.showID != nil ? String(ep.showID!) : UUID().uuidString)
            return "\(day.timeIntervalSince1970)_\(showID)"
        }
        
        for (_, episodes) in groupedByDayAndShow {
            guard let firstEp = episodes.first,
                  let airDate = firstEp.airDateAsDate else { continue }
            
            let day = calendar.startOfDay(for: airDate)
            
            // Try to find the associated MediaItem (the show)
            var item = firstEp.season?.tvShowDetails?.item
            if item == nil, let showID = firstEp.showID {
                let idStr = "tv_\(showID)"
                let desc = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == idStr })
                item = try? modelContext.fetch(desc).first
            }
            
            guard let foundItem = item else {
                print("⚠️ Calendar: Skipping episodes for unknown show ID \(firstEp.showID ?? 0)")
                continue
            }
            
            let season = firstEp.seasonNumber
            let sortedEpisodes = episodes.sorted { $0.episodeNumber < $1.episodeNumber }
            
            var context = ""
            if sortedEpisodes.count > 3 {
                context = "Season \(season)"
            } else {
                let epLabels = sortedEpisodes.map { "E\($0.episodeNumber)" }.joined(separator: ", ")
                context = "S\(season) \(epLabels)"
            }
            
            let releaseItem = CalendarReleaseItem(
                metadata: toMetadata(foundItem),
                releaseContext: context,
                date: airDate
            )
            dailyItems[day, default: []].append(releaseItem)
            allProcessedItems.append(releaseItem)
        }
        
        // 4. Finalize Day Infos
        var dayInfos: [Date: CalendarDayInfo] = [:]
        let maxPerDay = Double(dailyItems.values.map { $0.count }.max() ?? 1)
        
        var currentDate = startOfDay
        while currentDate <= endOfDay {
            let items = dailyItems[currentDate] ?? []
            let intensity = maxPerDay > 0 ? Double(items.count) / maxPerDay : 0
            
            dayInfos[currentDate] = CalendarDayInfo(
                date: currentDate,
                items: items,
                intensity: intensity
            )
            
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }
        
        return CalendarResult(
            days: dayInfos,
            allItems: allProcessedItems.sorted { $0.date < $1.date },
            startDate: startOfDay,
            endDate: endOfDay
        )
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
        let processedSearch = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        
        // 1. Simple Category-Based Predicate (Compiler Friendly)
        var basePredicate: Predicate<MediaItem>? = nil
        if let category = category {
            switch category {
            case "Upcoming": basePredicate = #Predicate<MediaItem> { $0.storedIsUpcoming == true }
            case "InProgress": basePredicate = #Predicate<MediaItem> { $0.stateValue == "Active" && $0.storedIsUpcoming == false }
            case "Watchlist": basePredicate = #Predicate<MediaItem> { $0.stateValue == "Wishlist" && $0.storedIsUpcoming == false }
            case "Loved": basePredicate = #Predicate<MediaItem> { $0.tasteValue == "Love" }
            case "Completed": basePredicate = #Predicate<MediaItem> { $0.stateValue == "Completed" }
            case "Archive": basePredicate = #Predicate<MediaItem> { $0.stateValue == "On Hold" || $0.stateValue == "Dropped" || $0.stateValue == "Re-watching" }
            case "Disliked": basePredicate = #Predicate<MediaItem> { $0.tasteValue == "Dislike" }
            case "Binge": basePredicate = #Predicate<MediaItem> { $0.storedIsBingeDrop == true || $0.storedSmartBadgeLabel == "BINGE" }
            default:
                if let type = MediaType(rawValue: category) {
                    let typeString = type.rawValue
                    basePredicate = #Predicate<MediaItem> { $0.typeValue == typeString }
                }
            }
        }
        
        var descriptor = FetchDescriptor<MediaItem>(predicate: basePredicate)
        
        if category == "Upcoming" {
            // For Upcoming category, we always want chronologically forward (soonest first)
            descriptor.sortBy = [SortDescriptor<MediaItem>(\.cachedNextAiringDate, order: .forward)]
        } else {
            switch sortOrder {
            case .alphabetical: descriptor.sortBy = [SortDescriptor<MediaItem>(\.title, order: .forward)]
            case .newestRelease: descriptor.sortBy = [SortDescriptor<MediaItem>(\.releaseDate, order: .reverse)]
            case .recentlyAdded: descriptor.sortBy = [SortDescriptor<MediaItem>(\.dateAdded, order: .reverse)]
            }
        }
        
        // Pagination only if no complex Swift-level filters
        let hasComplexFilters = !processedSearch.isEmpty || !(network?.isEmpty ?? true) || !(language?.isEmpty ?? true) || (genre != nil && !genre!.isEmpty)
        
        if !hasComplexFilters && groupBy == .none {
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset
        }
        
        var results = try modelContext.fetch(descriptor)
        
        // 2. Swift-Level Refinement
        if !processedSearch.isEmpty {
            let tokens = processedSearch.split(separator: " ").map(String.init)
            results = results.filter { item in
                let target = item.searchableText
                return tokens.allSatisfy { target.contains($0) }
            }
        }
        
        if let nets = network, !nets.isEmpty {
            let normalizedNets = Set(nets.map { $0.lowercased().trimmingCharacters(in: CharacterSet.whitespaces) })
            results = results.filter { item in
                guard let itemNet = item.cachedNetwork?.lowercased().trimmingCharacters(in: CharacterSet.whitespaces) else { return false }
                return normalizedNets.contains(itemNet)
            }
        }
        
        if let lang = language, !lang.isEmpty {
            results = results.filter { $0.cachedLanguage == lang }
        }

        if let g = genre, !g.isEmpty {
            results = results.filter { $0.cachedGenres.contains(g) }
        }

        let totalCount = (hasComplexFilters || groupBy != .none) ? 
                         results.count : 
                         (try? modelContext.fetchCount(FetchDescriptor<MediaItem>(predicate: basePredicate))) ?? results.count

        var featuredUpcoming: [MediaThumbnailMetadata] = []
        var homeContinueWatching: [MediaThumbnailMetadata] = []
        
        // 3. Specialized Logic
        if let category = category {
            if category == "Home" {
                let homePredicate = #Predicate<MediaItem> { item in
                    item.stateValue != "Completed" && item.tasteValue != "Dislike"
                }
                var homeDesc = FetchDescriptor<MediaItem>(predicate: homePredicate)
                homeDesc.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
                homeDesc.fetchLimit = 100 // Fetch a reasonable chunk for Home
                
                let homeResults = try modelContext.fetch(homeDesc)
                
                // Refine Home logic in Swift to avoid complex predicate compiler errors
                let activeItems = homeResults.filter { item in
                    let isActive = item.stateValue == "Active"
                    let airDate = item.cachedNextAiringDate ?? .distantPast
                    let isFuture = airDate > now
                    let isRecent = item.storedSmartBadgeLabel == "STREAMING" || item.storedIsBingeDrop == true
                    return (isActive && !isFuture) || isRecent
                }.sorted { itemA, itemB in
                    let isAStreaming = itemA.storedSmartBadgeLabel == "STREAMING"
                    let isBStreaming = itemB.storedSmartBadgeLabel == "STREAMING"
                    
                    if isAStreaming != isBStreaming {
                        return isAStreaming
                    }
                    
                    return (itemA.lastInteractionDate ?? .distantPast) > (itemB.lastInteractionDate ?? .distantPast)
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
                    grouped: [("Coming Soon", comingSoonItems.prefix(20).map { toMetadata($0) })], 
                    totalCount: totalCount
                )
            } else if category == "Upcoming" {
                featuredUpcoming = results.prefix(15).map { toMetadata($0) }
                results = Array(results.dropFirst(results.count > 15 ? 15 : 0))
            }
        }

        // 4. Grouping Logic
        var finalGroupedItems: [(String, [MediaThumbnailMetadata])] = []
        if groupBy != .none {
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
            finalGroupedItems = dict.map { ($0.key, $0.value.map { toMetadata($0) }) }
                .sorted { $0.0 < $1.0 }
        }

        // 3. Fetch Recently Added (Actually Recently Interacted/Watched)
        // We fetch this independently to ensure it's always sorted by interaction date
        // regardless of the main list's sort order.
        var recentAddedItems: [MediaThumbnailMetadata] = []
        if category != "Home" {
            var recentDesc = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.stateValue != "Wishlist" })
            recentDesc.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
            recentDesc.fetchLimit = 15
            
            if let recentItems = try? modelContext.fetch(recentDesc) {
                recentAddedItems = recentItems.filter { !$0.isDeleted }.prefix(10).map { toMetadata($0) }
            }
        }

        return PaginatedResult(
            displayed: results.map { toMetadata($0) },
            featuredUpcoming: featuredUpcoming,
            recentlyAdded: recentAddedItems,
            homeContinueWatching: homeContinueWatching,
            grouped: finalGroupedItems,
            totalCount: totalCount
        )
    }

    private func healMissingDates() async {
        let descriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.airDateValue == nil })
        let episodes = (try? modelContext.fetch(descriptor)) ?? []
        
        if !episodes.isEmpty {
            print("🔍 Calendar: Background date healing starting for \(episodes.count) episodes...")
            // Process in small batches and yield the actor to allow UI-critical fetches to run
            let batchSize = 50
            for i in stride(from: 0, to: episodes.count, by: batchSize) {
                let end = min(i + batchSize, episodes.count)
                let batch = episodes[i..<end]
                
                for episode in batch {
                    episode.updateAirDateValue()
                }
                
                try? modelContext.save()
                await Task.yield()
            }
        }
        
        let movies = (try? modelContext.fetch(FetchDescriptor<MediaItem>(predicate: #Predicate { $0.typeValue == "Movie" }))) ?? []
        for movie in movies {
            movie.syncCachedProperties()
        }
        
        try? modelContext.save()
        print("✅ Calendar: Background date healing completed.")
    }

    private func toMetadata(_ item: MediaItem) -> MediaThumbnailMetadata {
        MediaThumbnailMetadata(item: item)
    }
}
