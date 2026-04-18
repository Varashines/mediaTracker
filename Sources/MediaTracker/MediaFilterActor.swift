import Foundation
import SwiftData

@ModelActor
actor MediaFilterActor {
    func filterAndSort(
        category: String?,
        searchText: String,
        sortOrder: SortOrder,
        network: String?,
        language: String?,
        groupBy: GroupBy
    ) throws -> (displayedIDs: [PersistentIdentifier], recentlyAddedIDs: [PersistentIdentifier], groupedIDs: [(String, [PersistentIdentifier])]) {
        let fetchDescriptor = FetchDescriptor<MediaItem>()
        let items = try modelContext.fetch(fetchDescriptor)
        
        let validItems = items // No longer using soft-delete predicate
        
        var baseItems: [MediaItem]
        
        if category == "Upcoming" || category == nil {
            baseItems = validItems.filter { $0.isUpcoming }
                .sorted { item1, item2 in
                    guard let date1 = item1.cachedNextAiringDate else { return false }
                    guard let date2 = item2.cachedNextAiringDate else { return true }
                    return date1 < date2
                }
        } else if category == "InProgress" {
            baseItems = validItems.filter { $0.state == .active && !$0.isUpcoming }
        } else if category == "Waitlist" {
            baseItems = validItems.filter { $0.state == .wishlist && !$0.isUpcoming }
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
        
        var finalGroupedItems: [(String, [PersistentIdentifier])] = []
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
                (key, dict[key]!.map { $0.persistentModelID })
            }
        }
        
        return (
            displayedIDs: finalResults.map { $0.persistentModelID },
            recentlyAddedIDs: finalRecentlyAdded.map { $0.persistentModelID },
            groupedIDs: finalGroupedItems
        )
    }
}
