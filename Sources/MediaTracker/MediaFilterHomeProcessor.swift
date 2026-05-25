import Foundation
import SwiftData

// MARK: - Home Category Processing
// Extracted from MediaFilterActor to reduce file size (was 177 lines inline)

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
        descStreaming.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descStreaming.fetchLimit = 150
        
        var descTransition = FetchDescriptor<MediaItem>(predicate: pTransition)
        descTransition.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descTransition.fetchLimit = 50
        
        var descActiveOrRewatching = FetchDescriptor<MediaItem>(predicate: pActiveOrRewatching)
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
