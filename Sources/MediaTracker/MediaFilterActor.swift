import Foundation
import SwiftData

struct MediaThumbnailMetadata: Sendable, Identifiable {
    let id: PersistentIdentifier
    let title: String
    let posterURL: String?
    let releaseDate: Date?
    let state: MediaState?
    let type: MediaType?
    let cachedNextAiringDate: Date?
    let cachedNetwork: String?
    let badgeText: String?
    let watchProgress: String?
    let progress: Double?
    let isUpcoming: Bool
    let versionHash: Int
}

@ModelActor
actor MediaFilterActor {
    func filterAndSort(
        category: String?,
        searchText: String,
        sortOrder: SortOrder,
        network: String?,
        language: String?,
        groupBy: GroupBy
    ) throws -> (displayed: [MediaThumbnailMetadata], recentlyAdded: [MediaThumbnailMetadata], grouped: [(String, [MediaThumbnailMetadata])]) {
        let fetchDescriptor = FetchDescriptor<MediaItem>()
        let items = try modelContext.fetch(fetchDescriptor)
        
        // Settings Access (Note: ModelActor can't use @AppStorage directly)
        let nowWatchingDays = UserDefaults.standard.integer(forKey: "now_watching_days")
        let windowSeconds: TimeInterval = Double(max(nowWatchingDays, 1)) * 86400

        let validItems = items // No longer using soft-delete predicate
        
        var baseItems: [MediaItem]
        
        if category == "NowWatching" {
            baseItems = validItems.filter { item in
                guard item.state == .active && !item.isUpcoming else { return false }
                let interactionDate = item.lastInteractionDate ?? item.lastUpdated ?? item.dateAdded
                return Date().timeIntervalSince(interactionDate) <= windowSeconds
            }.sorted { 
                let d1 = $0.lastInteractionDate ?? $0.lastUpdated ?? $0.dateAdded
                let d2 = $1.lastInteractionDate ?? $1.lastUpdated ?? $1.dateAdded
                return d1 > d2
            }
        } else if category == "Upcoming" || category == nil {
            baseItems = validItems.filter { $0.isUpcoming }
                .sorted { item1, item2 in
                    guard let date1 = item1.cachedNextAiringDate else { return false }
                    guard let date2 = item2.cachedNextAiringDate else { return true }
                    return date1 < date2
                }
        } else if category == "InProgress" {
            baseItems = validItems.filter { $0.state == .active && !$0.isUpcoming }
                .sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        } else if category == "Watchlist" {
            baseItems = validItems.filter { $0.state == .wishlist && !$0.isUpcoming }
            .sorted { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        } else if category == "OnHold" {
            baseItems = validItems.filter { $0.state == .onHold }
        } else if category == "Dropped" {
            baseItems = validItems.filter { $0.state == .dropped }
        } else if category == "Rewatching" {
            baseItems = validItems.filter { $0.state == .rewatching }
        } else if category == "All" {
            baseItems = validItems
        } else {
            baseItems = validItems.filter { $0.type?.rawValue == category }
        }
        
        var results = baseItems
        
        if let net = network, !net.isEmpty {
            results = results.filter { $0.cachedNetwork == net }
        }
        
        if let lang = language, !lang.isEmpty {
            results = results.filter { $0.cachedLanguage == lang }
        }
        
        let isSortable = category == "All" || (category != nil && MediaType(rawValue: category!) != nil)
        if isSortable {
            switch sortOrder {
            case .alphabetical:
                results.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            case .newestRelease:
                results.sort { ($0.releaseDate ?? Date.distantPast) > ($1.releaseDate ?? Date.distantPast) }
            case .recentlyAdded:
                results.sort { $0.dateAdded > $1.dateAdded }
            }
        }
        
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            results = results.filter { $0.searchableText.contains(searchLower) }
        }
        
        let finalResults = results
        let finalRecentlyAdded = Array(validItems.sorted(by: { $0.dateAdded > $1.dateAdded }).prefix(5))
        
        // Helper to convert to lightweight metadata
        func toMetadata(_ item: MediaItem) -> MediaThumbnailMetadata {
            MediaThumbnailMetadata(
                id: item.persistentModelID,
                title: item.title,
                posterURL: item.posterURL,
                releaseDate: item.releaseDate,
                state: item.state,
                type: item.type,
                cachedNextAiringDate: item.cachedNextAiringDate,
                cachedNetwork: item.cachedNetwork,
                badgeText: item.badgeText,
                watchProgress: item.watchProgressLabel,
                progress: item.progress,
                isUpcoming: item.isUpcoming,
                versionHash: item.lastStateChangeDate.hashValue
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
        
        return (
            displayed: finalResults.map { toMetadata($0) },
            recentlyAdded: finalRecentlyAdded.map { toMetadata($0) },
            grouped: finalGroupedItems
        )
    }
}
