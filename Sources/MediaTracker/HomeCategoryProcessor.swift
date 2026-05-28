import Foundation
import SwiftData

extension MediaFilterActor {
    func processHomeCategory(now: Date, totalCount: Int) throws -> PaginatedResult {
        let newLabel = SmartBadge.new.rawValue
        let bingeLabel = SmartBadge.bingeDrop.rawValue
        let finaleLabel = SmartBadge.finale.rawValue
        let premiereLabel = SmartBadge.premiere.rawValue
        let dislikeLabel = TasteValue.dislike.rawValue
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

        let activeState = MediaState.activeRaw
        let rewatchingState = MediaState.rewatchingRaw
        let pActiveOrRewatching = #Predicate<MediaItem> { item in
            (item.stateValue == activeState || item.stateValue == rewatchingState) &&
            item.tasteValue != dislikeLabel
        }

        var descStreaming = FetchDescriptor<MediaItem>(predicate: pStreaming)
        descStreaming.propertiesToFetch = MediaItem.thumbnailPropertiesWithCast
        descStreaming.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descStreaming.fetchLimit = 150

        var descTransition = FetchDescriptor<MediaItem>(predicate: pTransition)
        descTransition.propertiesToFetch = MediaItem.thumbnailPropertiesWithCast
        descTransition.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descTransition.fetchLimit = 50

        var descActiveOrRewatching = FetchDescriptor<MediaItem>(predicate: pActiveOrRewatching)
        descActiveOrRewatching.propertiesToFetch = MediaItem.thumbnailPropertiesWithCast
        descActiveOrRewatching.sortBy = [SortDescriptor<MediaItem>(\.lastInteractionDate, order: .reverse)]
        descActiveOrRewatching.fetchLimit = 100

        let streamingItems = try modelContext.fetch(descStreaming)
        let transitionItems = try modelContext.fetch(descTransition)
        let activeItemsRaw = try modelContext.fetch(descActiveOrRewatching)

        let wishlistState = MediaState.wishlistRaw
        let recentPredicate = #Predicate<MediaItem> { item in
            item.stateValue == wishlistState && item.tasteValue != dislikeLabel
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

        let completedState = MediaState.completedRaw
        let droppedState = MediaState.droppedRaw
        let onHoldState = MediaState.onHoldRaw
        let activeStateVal = MediaState.activeRaw
        let rewatchingStateVal = MediaState.rewatchingRaw

        let activeItems = homeResults.filter { item in
            if item.stateValue == completedState || item.stateValue == droppedState || item.stateValue == onHoldState { return false }
            if item.storedIsUpcoming {
                let airDate = item.cachedNextAiringDate ?? .distantFuture
                if airDate > now { return false }
                let daysSinceAir = now.timeIntervalSince(airDate) / .secondsInDay
                if daysSinceAir > 14 { return false }
            }

            let isCaughtUp = (item.remainingEpisodesCount ?? 0) == 0
            let nextAirDate = item.cachedNextAiringDate ?? .distantPast
            if isCaughtUp && nextAirDate > now && item.type == .tvShow {
                return false
            }

            let isCurrentlyWatching = item.stateValue == activeStateVal || item.stateValue == rewatchingStateVal || (item.storedProgress ?? 0) > 0
            if isCurrentlyWatching {
                if (item.stateValue == activeStateVal || item.stateValue == rewatchingStateVal) && (item.storedProgress ?? 0) == 0 {
                    let lastInter = item.lastInteractionDate ?? .distantPast
                    let thirtyDaysAgo = now.addingTimeInterval(-.days30)
                    if lastInter < thirtyDaysAgo {
                        return false
                    }
                }
                return true
            }

            let badge = item.storedSmartBadgeLabel
            let isNewDrop = SmartBadge.radarBadges.contains(where: { $0.rawValue == badge })

            if isNewDrop {
                if item.stateValue == wishlistState && (item.storedProgress ?? 0) == 0 {
                    let releaseDate = item.cachedNextAiringDate ?? item.releaseDate ?? .distantPast
                    let daysSinceRelease = now.timeIntervalSince(releaseDate) / .secondsInDay
                    if daysSinceRelease > 5 {
                        return false
                    }
                }
                return true
            }
            return false
        }.sorted { (itemA: MediaItem, itemB: MediaItem) -> Bool in
            let badgeA = itemA.storedSmartBadgeLabel
            let isRecentA = SmartBadge.recentBadges.contains(where: { $0.rawValue == badgeA })
            let badgeB = itemB.storedSmartBadgeLabel
            let isRecentB = SmartBadge.recentBadges.contains(where: { $0.rawValue == badgeB })

            if isRecentA != isRecentB { return isRecentA }

            let isAActive = itemA.stateValue == activeStateVal || itemA.stateValue == rewatchingStateVal || (itemA.storedProgress ?? 0) > 0
            let isBActive = itemB.stateValue == activeStateVal || itemB.stateValue == rewatchingStateVal || (itemB.storedProgress ?? 0) > 0
            if isAActive != isBActive { return isAActive }

            let isAPremiere = itemA.storedSmartBadgeLabel == SmartBadge.premiere.rawValue
            let isBPremiere = itemB.storedSmartBadgeLabel == SmartBadge.premiere.rawValue
            if isAPremiere != isBPremiere { return isAPremiere }

            let isAStreaming = itemA.storedSmartBadgeLabel == SmartBadge.new.rawValue
            let isBStreaming = itemB.storedSmartBadgeLabel == SmartBadge.new.rawValue
            if isAStreaming != isBStreaming { return isAStreaming }

            let isAFinale = itemA.storedSmartBadgeLabel == SmartBadge.finale.rawValue
            let isBFinale = itemB.storedSmartBadgeLabel == SmartBadge.finale.rawValue
            if isAFinale != isBFinale { return isAFinale }

            let isABinge = itemA.storedSmartBadgeLabel == SmartBadge.bingeDrop.rawValue
            let isBBinge = itemB.storedSmartBadgeLabel == SmartBadge.bingeDrop.rawValue
            if isABinge != isBBinge { return isABinge }

            let dateA = itemA.lastInteractionDate ?? .distantPast
            let dateB = itemB.lastInteractionDate ?? .distantPast

            if dateA != dateB {
                return dateA > dateB
            }

            return itemA.title < itemB.title
        }

        let spotlight = activeItems.first { $0.stateValue == activeStateVal }
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
