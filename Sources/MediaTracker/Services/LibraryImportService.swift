import Foundation
import SwiftData

// Library import — restore from backup files. Extension of the shared
// BackgroundDataService actor (split from it; see that file for orchestration).


enum ImportConflictStrategy: String, CaseIterable, Identifiable, Sendable {
    case merge = "Merge"
    case overwrite = "Overwrite"
    case skip = "Skip"

    var id: String { rawValue }

    var title: String { rawValue }

    var description: String {
        switch self {
        case .merge: return "Keep existing items, fill in missing fields from backup"
        case .overwrite: return "Replace existing matching items with backup version"
        case .skip: return "Only add new items, preserve existing items untouched"
        }
    }
}

struct ImportProgress: Sendable {
    let processedCount: Int
    let totalCount: Int
    let importedCount: Int
    let mergedCount: Int
    let skippedCount: Int
    let currentTitle: String
    let isCancelled: Bool
    let isFinished: Bool
}
extension BackgroundDataService {
    func importLibraryData(
        backup: LibraryBackup,
        strategy: ImportConflictStrategy = .skip,
        triggerPostImportBackfill: Bool = true,
        onProgress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async -> (imported: Int, merged: Int, skipped: Int, itemsNeedingBackfill: [String]) {
        let context = modelContext
        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = [\.id, \.typeValue]
        let existingItems = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(
            uniqueKeysWithValues: existingItems.map {
                (MediaItemData.importKey(id: $0.id, typeRawValue: $0.type?.rawValue ?? ""), $0)
            }
        )

        // Batched lookups replace per-season/per-episode FetchDescriptor calls (N+1).
        let seasonFetch = FetchDescriptor<TVSeason>()
        var existingSeasonsByUniqueID: [String: TVSeason] = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(seasonFetch)) ?? []).compactMap { season in
                season.uniqueID.map { ($0, season) }
            }
        )
        let episodeFetch = FetchDescriptor<TVEpisode>()
        var existingEpisodesByUniqueID: [String: TVEpisode] = Dictionary(
            uniqueKeysWithValues: ((try? context.fetch(episodeFetch)) ?? []).compactMap { episode in
                episode.uniqueID.map { ($0, episode) }
            }
        )

        var importedCount = 0
        var mergedCount = 0
        var skippedCount = 0
        var processedCount = 0
        var itemsNeedingBackfill: [String] = []
        
        let totalCount = backup.items.count
        
        for itemData in backup.items {
            if Task.isCancelled {
                onProgress?(ImportProgress(
                    processedCount: processedCount,
                    totalCount: totalCount,
                    importedCount: importedCount,
                    mergedCount: mergedCount,
                    skippedCount: skippedCount,
                    currentTitle: itemData.title,
                    isCancelled: true,
                    isFinished: false
                ))
                return (importedCount, mergedCount, skippedCount, itemsNeedingBackfill)
            }
            
            let mediaType = MediaItemData.canonicalMediaType(for: itemData.type, id: itemData.id)
            let uniqueID = MediaItemData.canonicalID(itemData.id, type: mediaType)
            let tmdbIDPart = uniqueID.split(separator: "_").last ?? uniqueID[...]
            let key = MediaItemData.importKey(id: uniqueID, typeRawValue: mediaType.rawValue)
            let watchedDates = itemData.watchedEpisodeDates ?? [:]

            if let existing = existingMap[key] {
                let hasDetails = (existing.type == .movie && existing.movieDetails != nil)
                    || (existing.type == .tvShow && existing.tvShowDetails != nil && !existing.cachedGenres.isEmpty)
                switch strategy {
                case .skip:
                    skippedCount += 1
                case .merge:
                    if existing.tasteValue == TasteValue.none.rawValue, let newTaste = itemData.taste {
                        existing.tasteValue = newTaste
                    }
                    if itemData.dateAdded < (existing.dateAdded ?? .distantFuture) {
                        existing.dateAdded = itemData.dateAdded
                    }
                    if let backupDate = itemData.lastInteractionDate,
                       backupDate > (existing.lastInteractionDate ?? .distantPast) {
                        existing.lastInteractionDate = backupDate
                    }
                    if let backupStateDate = itemData.lastStateChangeDate {
                        existing.lastStateChangeDate = backupStateDate
                    }
                    itemData.applyMetadata(to: existing, preserveLastUpdated: hasDetails)
                    if !hasDetails { itemsNeedingBackfill.append(existing.id) }
                    existing.syncCachedProperties(dirty: .all)
                    mergedCount += 1
                case .overwrite:
                    existing.state = MediaState(rawValue: itemData.state) ?? .wishlist
                    if let backupStateDate = itemData.lastStateChangeDate {
                        existing.lastStateChangeDate = backupStateDate
                    }
                    existing.dateAdded = itemData.dateAdded
                    existing.tasteValue = itemData.taste ?? TasteValue.none.rawValue
                    existing.lastInteractionDate = itemData.lastInteractionDate ?? existing.lastInteractionDate
                    itemData.applyMetadata(to: existing, preserveLastUpdated: hasDetails)
                    if !hasDetails { itemsNeedingBackfill.append(existing.id) }
                    existing.syncCachedProperties(dirty: .all)
                    if mediaType == .movie,
                       itemData.state == MediaState.completedRaw {
                        let watchedAt = itemData.lastStateChangeDate ?? itemData.dateAdded
                        WatchHistoryCoordinator.recordImportedMovie(
                            mediaID: existing.id,
                            watchedAt: watchedAt,
                            runtimeMinutes: existing.cachedRuntime,
                            context: context
                        )
                    }
                    mergedCount += 1
                }
                if strategy != .skip {
                    itemData.applySeasonTasteOverrides(to: existing, in: context, mergeOnlyIfEmpty: strategy == .merge)
                }
            } else {
                let item = MediaItem(
                    id: uniqueID,
                    title: itemData.title,
                    overview: "",
                    posterURL: nil,
                    releaseDate: nil,
                    type: mediaType
                )
                item.state = MediaState(rawValue: itemData.state) ?? .wishlist
                if let backupStateDate = itemData.lastStateChangeDate {
                    item.lastStateChangeDate = backupStateDate
                }
                item.dateAdded = itemData.dateAdded
                item.tasteValue = itemData.taste ?? TasteValue.none.rawValue
                item.lastInteractionDate = itemData.lastInteractionDate
                itemData.applyMetadata(to: item, preserveLastUpdated: false)
                itemsNeedingBackfill.append(uniqueID)
                item.syncCachedProperties(dirty: .all)
                context.insert(item)
                if mediaType == .movie,
                   itemData.state == MediaState.completedRaw {
                    let watchedAt = itemData.lastStateChangeDate ?? itemData.dateAdded
                    WatchHistoryCoordinator.recordImportedMovie(
                        mediaID: item.id,
                        watchedAt: watchedAt,
                        runtimeMinutes: item.cachedRuntime,
                        context: context
                    )
                }
                importedCount += 1

                itemData.applySeasonTasteOverrides(to: item, in: context)

                // Restore Episode Progress
                if item.type == .tvShow, let watchedIDs = itemData.watchedEpisodeIDs, let tmdbID = Int(tmdbIDPart) {
                    var seasonEpisodes: [Int: Set<Int>] = [:]
                    for epID in watchedIDs {
                        let parts = epID.split(separator: "_")
                        if parts.count == 3,
                           let sNum = Int(parts[1]),
                           let eNum = Int(parts[2]) {
                            seasonEpisodes[sNum, default: []].insert(eNum)
                        }
                    }

                    for (sNum, watchedNumbers) in seasonEpisodes {
                        let seasonUniqueID = "\(tmdbID)_\(sNum)"
                        let season = existingSeasonsByUniqueID[seasonUniqueID] ?? {
                            let newSeason = TVSeason(seasonNumber: sNum, name: "Season \(sNum)", episodeCount: 0, airDate: nil)
                            newSeason.uniqueID = seasonUniqueID
                            newSeason.showID = tmdbID
                            newSeason.tvShowDetails = nil
                            context.insert(newSeason)
                            existingSeasonsByUniqueID[seasonUniqueID] = newSeason
                            return newSeason
                        }()

                        for eNum in watchedNumbers {
                            let epUniqueID = "\(tmdbID)_\(sNum)_\(eNum)"
                            if let existing = existingEpisodesByUniqueID[epUniqueID], existing.modelContext != nil {
                                let watchedAt = watchedDates[epUniqueID]
                                existing.applyImportedWatchState(watchedAt: watchedAt)
                                let eventDate = watchedAt ?? existing.watchedDate ?? existing.lastWatchedDate ?? item.dateAdded ?? Date()
                                WatchHistoryCoordinator.recordImportedEpisode(
                                    mediaID: uniqueID,
                                    episodeID: epUniqueID,
                                    watchedAt: eventDate,
                                    runtimeMinutes: existing.runtime,
                                    context: context
                                )
                                continue
                            }
                            let episode = TVEpisode(
                                episodeNumber: eNum, seasonNumber: sNum,
                                name: "Episode \(eNum)", overview: "",
                                airDate: nil, runtime: nil,
                                isWatched: true, showID: tmdbID
                            )
                            episode.uniqueID = epUniqueID
                            episode.season = season
                            let watchedAt = watchedDates[epUniqueID] ?? item.dateAdded ?? Date()
                            episode.applyImportedWatchState(watchedAt: watchedAt)
                            context.insert(episode)
                            existingEpisodesByUniqueID[epUniqueID] = episode
                            WatchHistoryCoordinator.recordImportedEpisode(
                                mediaID: uniqueID,
                                episodeID: epUniqueID,
                                watchedAt: watchedAt,
                                runtimeMinutes: episode.runtime,
                                context: context
                            )
                        }
                    }
                }
            }
            
            processedCount += 1
            if processedCount % 25 == 0 || processedCount == totalCount {
                // Intentional batch save inside import loop — SaveCoordinator's
                // 350ms debounce would coalesce 25-item checkpoints into one
                // late save and lose progress granularity / crash-safety.
                do { try context.save() } catch {
                    AppLogger.warning("Import intermediate save failed: \(error)", logger: AppLogger.sync)
                }
                onProgress?(ImportProgress(
                    processedCount: processedCount,
                    totalCount: totalCount,
                    importedCount: importedCount,
                    mergedCount: mergedCount,
                    skippedCount: skippedCount,
                    currentTitle: itemData.title,
                    isCancelled: false,
                    isFinished: processedCount == totalCount
                ))
            }
        }
        
        // Intentional final batch save — import must be durable before backfill Tasks.
        do { try context.save() } catch {
            AppLogger.warning("Import final save failed: \(error)", logger: AppLogger.sync)
        }

        // Post-import comprehensive backfill for genres, cast/directors, episode data and air dates
        if triggerPostImportBackfill && (importedCount > 0 || mergedCount > 0) {
            let idsToBackfill = itemsNeedingBackfill
            Task.detached(priority: .background) {
                await BackgroundTaskManager.shared.backfillMissingLibraryMetadata(priorityIDs: idsToBackfill)
                await BackgroundTaskManager.shared.refreshMissingAirDates(cap: 50)
                await BackgroundTaskManager.shared.refreshStalePremiereBadges()
            }
        }
        onProgress?(ImportProgress(
            processedCount: totalCount,
            totalCount: totalCount,
            importedCount: importedCount,
            mergedCount: mergedCount,
            skippedCount: skippedCount,
            currentTitle: "",
            isCancelled: false,
            isFinished: true
        ))
        return (importedCount, mergedCount, skippedCount, itemsNeedingBackfill)
    }

    func importCollections(backup: LibraryBackup) async {
        guard let collectionData = backup.collections, !collectionData.isEmpty else { return }

        let context = modelContext
        let existingDescriptor = FetchDescriptor<MediaCollection>()
        let existingCollections = (try? context.fetch(existingDescriptor)) ?? []
        let existingIDs = Set(existingCollections.map { $0.id })

        var importedCount = 0

        for colData in collectionData where !existingIDs.contains(colData.id) {
            let collection = MediaCollection(name: colData.name, systemImage: colData.systemImage, isSmart: colData.smartRulesData != nil)
            collection.id = colData.id
            collection.notes = colData.notes
            collection.isPinned = colData.isPinned
            collection.completedItemIDs = colData.completedItemIDs
            collection.smartRulesData = colData.smartRulesData
            context.insert(collection)

            if colData.smartRulesData == nil, let itemIDs = colData.itemIDs, !itemIDs.isEmpty {
                let idSet = Set(itemIDs)
                let batchDescriptor = FetchDescriptor<MediaItem>(predicate: #Predicate<MediaItem> { idSet.contains($0.id) })
                let fetchedItems = (try? context.fetch(batchDescriptor)) ?? []
                let itemsByID = Dictionary<String, MediaItem>(uniqueKeysWithValues: fetchedItems.map { ($0.id, $0) })
                for itemID in itemIDs {
                    if let item = itemsByID[itemID], item.modelContext != nil {
                        collection.items.append(item)
                    }
                }
            }

            importedCount += 1
        }

        if importedCount > 0 {
            // Intentional batch save — collection restore is a bulk write off the UI frame.
            try? context.save()
            await MainActor.run {
                AppLogger.info("📦 Restored \(importedCount) collections from backup.", logger: AppLogger.data)
            }
        }
    }

}
