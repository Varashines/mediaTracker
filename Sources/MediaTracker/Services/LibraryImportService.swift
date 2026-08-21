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
        onProgress: (@Sendable (ImportProgress) -> Void)? = nil
    ) async -> (imported: Int, merged: Int, skipped: Int) {
        let context = modelContext
        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = [\.id, \.typeValue]
        let existingItems = (try? context.fetch(descriptor)) ?? []
        let existingMap = Dictionary(
            uniqueKeysWithValues: existingItems.map {
                (MediaItemData.importKey(id: $0.id, typeRawValue: $0.type?.rawValue ?? ""), $0)
            }
        )

        // Pre-scan: collect unique (tmdbID, seasonNumber) work for episode-progress restore
        // so seasons/episodes can be fetched in bulk and season payloads resolved via a
        // bounded network-only task group instead of per-item awaits inside the loop.
        var seasonWork = Set<String>()
        var seasonWorkPairs: [(tmdbID: Int, seasonNumber: Int)] = []
        for itemData in backup.items {
            let mediaType = MediaItemData.canonicalMediaType(for: itemData.type, id: itemData.id)
            guard mediaType == .tvShow,
                  let watchedIDs = itemData.watchedEpisodeIDs, !watchedIDs.isEmpty else { continue }
            let uniqueID = MediaItemData.canonicalID(itemData.id, type: mediaType)
            let tmdbIDPart = uniqueID.split(separator: "_").last ?? uniqueID[...]
            guard let tmdbID = Int(tmdbIDPart) else { continue }
            for epID in watchedIDs {
                let parts = epID.split(separator: "_")
                if parts.count == 3, let sNum = Int(parts[1]), seasonWork.insert("\(tmdbID)_\(sNum)").inserted {
                    seasonWorkPairs.append((tmdbID, sNum))
                }
            }
        }

        // Batched lookups replace per-season/per-episode FetchDescriptor calls (N+1).
        // Entries inserted during this import are also recorded here so later items
        // in the same backup resolve against them.
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

        // Resolve missing TMDB season payloads network-only (no model mutation in the group),
        // bounded to 6 concurrent requests; applied serially in the import loop below.
        var seasonPayloads: [String: [TVEpisodeResult]] = [:]
        if !seasonWorkPairs.isEmpty {
            let maxConcurrent = 6
            var index = 0
            while index < seasonWorkPairs.count {
                let batch = seasonWorkPairs[index..<min(index + maxConcurrent, seasonWorkPairs.count)]
                index += maxConcurrent
                await withTaskGroup(of: (String, [TVEpisodeResult]?).self) { group in
                    for pair in batch {
                        group.addTask {
                            do {
                                let details = try await APIClient.shared.fetchSeasonDetails(tmdbID: pair.tmdbID, seasonNumber: pair.seasonNumber)
                                return ("\(pair.tmdbID)_\(pair.seasonNumber)", details)
                            } catch {
                                AppLogger.warning("Season prefetch failed for tmdbID=\(pair.tmdbID) season=\(pair.seasonNumber): \(error)", logger: AppLogger.sync)
                                return ("\(pair.tmdbID)_\(pair.seasonNumber)", nil)
                            }
                        }
                    }
                    for await (key, payload) in group {
                        if let payload { seasonPayloads[key] = payload }
                    }
                }
            }
        }

        var importedCount = 0
        var mergedCount = 0
        var skippedCount = 0
        var processedCount = 0
        
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
                return (importedCount, mergedCount, skippedCount)
            }
            
            let mediaType = MediaItemData.canonicalMediaType(for: itemData.type, id: itemData.id)
            let uniqueID = MediaItemData.canonicalID(itemData.id, type: mediaType)
            let tmdbIDPart = uniqueID.split(separator: "_").last ?? uniqueID[...]
            let key = MediaItemData.importKey(id: uniqueID, typeRawValue: mediaType.rawValue)
            let watchedDates = itemData.watchedEpisodeDates ?? [:]

            if let existing = existingMap[key] {
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
                    itemData.applyMetadata(to: existing)
                    existing.syncCachedProperties(dirty: .all)
                    mergedCount += 1
                case .overwrite:
                    existing.state = MediaState(rawValue: itemData.state) ?? .wishlist
                    existing.dateAdded = itemData.dateAdded
                    existing.tasteValue = itemData.taste ?? TasteValue.none.rawValue
                    existing.lastInteractionDate = itemData.lastInteractionDate ?? existing.lastInteractionDate
                    itemData.applyMetadata(to: existing)
                    existing.syncCachedProperties(dirty: .all)
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
                item.dateAdded = itemData.dateAdded
                item.tasteValue = itemData.taste ?? TasteValue.none.rawValue
                item.lastInteractionDate = itemData.lastInteractionDate
                itemData.applyMetadata(to: item)
                item.syncCachedProperties(dirty: .all)
                context.insert(item)
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

                        guard let seasonData = seasonPayloads[seasonUniqueID] else {
                            for eNum in watchedNumbers {
                                let epUniqueID = "\(tmdbID)_\(sNum)_\(eNum)"
                                if let existing = existingEpisodesByUniqueID[epUniqueID], existing.modelContext != nil {
                                    existing.markWatched(true)
                                    if let d = watchedDates[epUniqueID] { existing.lastWatchedDate = d }
                                    continue
                                }
                                let episode = TVEpisode(
                                    episodeNumber: eNum, seasonNumber: sNum,
                                    name: "Episode \(eNum)", overview: "",
                                    airDate: nil, runtime: nil,
                                    isWatched: true, showID: tmdbID
                                )
                                episode.uniqueID = epUniqueID
                                episode.lastWatchedDate = watchedDates[epUniqueID]
                                episode.season = season
                                context.insert(episode)
                                existingEpisodesByUniqueID[epUniqueID] = episode
                            }
                            continue
                        }

                        season.episodeCount = seasonData.count

                        for epData in seasonData {
                            let epUniqueID = "\(tmdbID)_\(sNum)_\(epData.episodeNumber)"
                            if let existing = existingEpisodesByUniqueID[epUniqueID], existing.modelContext != nil {
                                existing.name = epData.name ?? "Episode \(epData.episodeNumber)"
                                existing.overview = epData.overview ?? ""
                                if let runtime = epData.runtime { existing.runtime = runtime }
                                if let airDate = epData.airDate { existing.airDate = airDate }
                                existing.season = season
                                if watchedNumbers.contains(epData.episodeNumber) {
                                    existing.markWatched(true)
                                    if let d = watchedDates[epUniqueID] { existing.lastWatchedDate = d }
                                }
                                continue
                            }

                            let episode = TVEpisode(
                                episodeNumber: epData.episodeNumber,
                                seasonNumber: sNum,
                                name: epData.name ?? "Episode \(epData.episodeNumber)",
                                overview: epData.overview ?? "",
                                airDate: epData.airDate,
                                runtime: epData.runtime,
                                isWatched: watchedNumbers.contains(epData.episodeNumber),
                                showID: tmdbID
                            )
                            episode.uniqueID = epUniqueID
                            if watchedNumbers.contains(epData.episodeNumber) {
                                episode.lastWatchedDate = watchedDates[epUniqueID]
                            }
                            episode.season = season
                            context.insert(episode)
                            existingEpisodesByUniqueID[epUniqueID] = episode
                        }
                    }
                }
            }
            
            processedCount += 1
            if processedCount % 25 == 0 || processedCount == totalCount {
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
        
        do { try context.save() } catch {
            AppLogger.warning("Import final save failed: \(error)", logger: AppLogger.sync)
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
        return (importedCount, mergedCount, skippedCount)
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
            try? context.save()
            await MainActor.run {
                AppLogger.info("📦 Restored \(importedCount) collections from backup.", logger: AppLogger.data)
            }
        }
    }

}
