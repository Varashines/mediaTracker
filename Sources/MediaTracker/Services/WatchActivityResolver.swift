import Foundation
import SwiftData

struct WatchActivityCandidate: Sendable {
    let id: PersistentIdentifier
    let mediaID: String
    let title: String
    let type: MediaType
    let watchedAt: Date
}

enum WatchActivityResolver {
    static func latestWatchDate(for item: MediaItem, context: ModelContext) -> Date? {
        latestWatchDates(for: [item], context: context)[item.id]
    }

    static func latestWatchDates(for items: [MediaItem], context: ModelContext) -> [String: Date] {
        guard !items.isEmpty else { return [:] }
        var dates: [String: Date] = [:]
        let mediaIDs = Set(items.map(\.id))

        var eventDescriptor = FetchDescriptor<WatchEvent>(
            predicate: #Predicate<WatchEvent> { event in
                mediaIDs.contains(event.mediaID) && event.voidedAt == nil
            }
        )
        eventDescriptor.propertiesToFetch = [\.mediaID, \.episodeID, \.watchedAt, \.voidedAt]
        if let events = try? context.fetch(eventDescriptor) {
            for event in events {
                guard event.isActive else { continue }
                dates[event.mediaID] = max(dates[event.mediaID] ?? .distantPast, event.watchedAt)
            }
        }

        let showIDs = Set(items.compactMap { item -> Int? in
            guard item.type == .tvShow else { return nil }
            return Int(item.id.split(separator: "_").last ?? "")
        })
        if !showIDs.isEmpty {
            var episodeDescriptor = FetchDescriptor<TVEpisode>(
                predicate: #Predicate<TVEpisode> { episode in
                    episode.isWatched
                }
            )
            episodeDescriptor.propertiesToFetch = [\.showID, \.isWatched, \.watchedDate, \.lastWatchedDate]
            if let episodes = try? context.fetch(episodeDescriptor) {
                for episode in episodes {
                    guard let showID = episode.showID,
                          showIDs.contains(showID),
                          let date = episode.watchedDate ?? episode.lastWatchedDate else { continue }
                    let mediaID = "tv_\(showID)"
                    dates[mediaID] = max(dates[mediaID] ?? .distantPast, date)
                }
            }
        }

        for item in items where dates[item.id] == nil && item.type == .movie && item.state == .completed {
            if let date = item.lastStateChangeDate {
                dates[item.id] = date
            }
        }

        return dates
    }

    static func candidates(type: MediaType, context: ModelContext) -> [WatchActivityCandidate] {
        candidates(types: [type], context: context)
    }

    static func candidates(types: [MediaType], context: ModelContext) -> [WatchActivityCandidate] {
        let rawTypes = Set(types.map(\.rawValue))
        let wishlist = MediaState.wishlistRaw
        let predicate = #Predicate<MediaItem> { item in
            item.isSoftDeleted == false && rawTypes.contains(item.typeValue) && item.stateValue != wishlist
        }
        let batchSize = LibraryScanLimits.refinementBatchSize
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
        descriptor.propertiesToFetch = MediaItem.thumbnailProperties
        descriptor.fetchLimit = batchSize
        var offset = 0
        descriptor.fetchOffset = offset

        var items: [MediaItem] = []
        while true {
            if Task.isCancelled { break }
            let batch = (try? context.fetch(descriptor)) ?? []
            items.append(contentsOf: batch)
            guard batch.count == batchSize else { break }
            offset += batchSize
            descriptor.fetchOffset = offset
        }
        let dates = latestWatchDates(for: items, context: context)
        return items.compactMap { item in
            guard let date = dates[item.id] else { return nil }
            return WatchActivityCandidate(
                id: item.persistentModelID,
                mediaID: item.id,
                title: item.title,
                type: item.type ?? .movie,
                watchedAt: date
            )
        }
        .sorted {
            if $0.watchedAt != $1.watchedAt { return $0.watchedAt > $1.watchedAt }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func recentItemIDs(
        type: MediaType,
        cutoff: Date,
        limit: Int,
        context: ModelContext
    ) -> [PersistentIdentifier] {
        recentItemIDs(
            candidates: candidates(type: type, context: context),
            cutoff: cutoff,
            limit: limit
        )
    }

    static func recentCandidates(
        candidates: [WatchActivityCandidate],
        cutoff: Date,
        limit: Int
    ) -> [WatchActivityCandidate] {
        Array(candidates.lazy.filter { $0.watchedAt >= cutoff }.prefix(limit))
    }

    static func recentItemIDs(
        candidates: [WatchActivityCandidate],
        cutoff: Date,
        limit: Int
    ) -> [PersistentIdentifier] {
        recentCandidates(candidates: candidates, cutoff: cutoff, limit: limit).map(\.id)
    }
}
