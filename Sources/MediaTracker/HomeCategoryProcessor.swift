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

        var seenIDs = Set<PersistentIdentifier>()
        var homeResults: [MediaItem] = []
        for item in (streamingItems + transitionItems + activeItemsRaw + recentItems) {
            if seenIDs.insert(item.persistentModelID).inserted {
                homeResults.append(item)
            }
        }

        let activeItems = homeResults.filter { isHomeEligible($0, now: now) }
            .sorted { a, b in
                let pa = homeSortPriority(a)
                let pb = homeSortPriority(b)
                if pa != pb { return pa > pb }
                return (a.lastInteractionDate ?? .distantPast) > (b.lastInteractionDate ?? .distantPast)
            }

        let spotlight = activeItems.first { $0.stateValue == MediaState.activeRaw }
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

    private func isHomeEligible(_ item: MediaItem, now: Date) -> Bool {
        if item.stateValue == MediaState.completedRaw ||
           item.stateValue == MediaState.droppedRaw ||
           item.stateValue == MediaState.onHoldRaw { return false }

        if item.storedIsUpcoming {
            let airDate = item.cachedNextAiringDate ?? .distantFuture
            if airDate > now { return false }
            let daysSinceAir = now.timeIntervalSince(airDate) / .secondsInDay
            if daysSinceAir > 14 { return false }
        }

        let isCaughtUp = (item.remainingEpisodesCount ?? 0) == 0
        let nextAirDate = item.cachedNextAiringDate ?? .distantPast
        if isCaughtUp && nextAirDate > now && item.type == .tvShow { return false }

        let isActive = item.stateValue == MediaState.activeRaw ||
                       item.stateValue == MediaState.rewatchingRaw ||
                       (item.storedProgress ?? 0) > 0
        if isActive {
            if (item.stateValue == MediaState.activeRaw || item.stateValue == MediaState.rewatchingRaw) &&
               (item.storedProgress ?? 0) == 0 {
                let lastInter = item.lastInteractionDate ?? .distantPast
                if lastInter < now.addingTimeInterval(-.days30) { return false }
            }
            return true
        }

        let badge = item.storedSmartBadgeLabel
        let isNewDrop = SmartBadge.radarBadges.contains(where: { $0.rawValue == badge })
        if isNewDrop {
            if item.stateValue == MediaState.wishlistRaw && (item.storedProgress ?? 0) == 0 {
                let releaseDate = item.cachedNextAiringDate ?? item.releaseDate ?? .distantPast
                let daysSinceRelease = now.timeIntervalSince(releaseDate) / .secondsInDay
                if daysSinceRelease > 5 { return false }
            }
            return true
        }
        return false
    }

    private func homeSortPriority(_ item: MediaItem) -> Int {
        let badge = item.storedSmartBadgeLabel
        let isRecent = SmartBadge.recentBadges.contains(where: { $0.rawValue == badge })

        if isRecent {
            if badge == SmartBadge.premiere.rawValue { return 110 }
            if badge == SmartBadge.new.rawValue { return 100 }
            if badge == SmartBadge.finale.rawValue { return 95 }
            if badge == SmartBadge.bingeDrop.rawValue { return 90 }
            return 85
        }

        let isActive = item.stateValue == MediaState.activeRaw ||
                       item.stateValue == MediaState.rewatchingRaw ||
                       (item.storedProgress ?? 0) > 0
        if isActive { return 80 }
        return 0
    }
}
