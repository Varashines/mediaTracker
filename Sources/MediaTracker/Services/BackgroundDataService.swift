import Foundation
import SwiftData
import UserNotifications
import AppKit

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

@ModelActor
actor BackgroundDataService {
    private var isThermalThrottled: Bool {
        // Phase 1 Optimization: Thermal Awareness for fanless M1 Air
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            return true
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return true
        }
        return false
    }

    func createNewMediaItem(uniqueID: String, tmdbID: Int, type: MediaType, title: String, overview: String, posterURL: String?, releaseDateString: String?) async -> (id: PersistentIdentifier?, isExisting: Bool) {
        // 1. Background uniqueness check
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate<MediaItem> { $0.id == uniqueID })
        if let existing = try? modelContext.fetch(descriptor).first {
            return (existing.persistentModelID, true)
        }

        // 2. Create the item
        let releaseDate = releaseDateString != nil ? DateUtils.parseDate(releaseDateString) : nil
        let item = MediaItem(
            id: uniqueID, title: title, overview: overview,
            posterURL: posterURL, releaseDate: releaseDate, type: type)
        item.dateAdded = Date()
        modelContext.insert(item)

        // 3. Fetch full details immediately (force: true to avoid cached nil-poster responses)
        if type == .movie {
            _ = await self.refreshMovie(id: uniqueID, tmdbID: tmdbID, force: true)
        } else if type == .tvShow {
            _ = await self.refreshTVShow(id: uniqueID, tmdbID: tmdbID, force: true)
        }
        
        item.syncCachedProperties(dirty: .all)
        try? modelContext.save()
        return (item.persistentModelID, false)
    }

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

    func deleteMediaItem(id: String) async {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        
        let posterURL = item.posterURL
        let backdropURL = item.backdropURL
        let typePrefix = item.type == .movie ? "movie" : "tv"
        let tmdbID = item.id.split(separator: "_").last ?? ""
        
        // Clean up completedItemIDs in all collections before delete
        let allCollectionsDescriptor = FetchDescriptor<MediaCollection>()
        if let allCollections = try? modelContext.fetch(allCollectionsDescriptor) {
            for collection in allCollections {
                collection.completedItemIDs.removeAll { $0 == id }
            }
        }
        
        modelContext.delete(item)
        
        do {
            try modelContext.save()
            AppLogger.info("🗑️ Cascade Deletion: Deleted \(id) and all associated records.", logger: AppLogger.background)
        } catch {
            Task { @MainActor in AppErrorState.shared.surfaceError("Failed to delete item: \(error.localizedDescription)") }
        }
        
        await ImageCache.shared.removeImage(forKey: posterURL)
        await ImageCache.shared.removeImage(forKey: backdropURL)
        
        // Purge API detail cache so re-adding fetches fresh data
        if !tmdbID.isEmpty {
            APIClient.shared.removeCachedResponse(forKey: "\(typePrefix)_details_\(tmdbID).json")
            APIClient.shared.removeCachedResponse(forKey: "\(typePrefix)_details_v2_\(tmdbID).json")
        }
    }

    func clearDatabase() async {
        do {
            try modelContext.delete(model: MediaItem.self)
            try modelContext.delete(model: NetworkEntity.self)
            try modelContext.delete(model: GenreEntity.self)
            try modelContext.delete(model: LanguageEntity.self)
            try modelContext.delete(model: MediaCollection.self)
            try modelContext.delete(model: BadgeEntity.self)
            try modelContext.delete(model: PersonImageEntity.self)
            try modelContext.delete(model: StudioAliasEntity.self)
            try modelContext.delete(model: SearchCacheEntity.self)
            try modelContext.delete(model: ProviderEntity.self)
            try modelContext.save()
            
            // Clear caches as well
            await ImageCache.shared.clearFullCache()
            URLCache.shared.removeAllCachedResponses()
            
            AppLogger.info("✅ Database cleared successfully.", logger: AppLogger.background)
        } catch {
            Task { @MainActor in AppErrorState.shared.surfaceError("Failed to clear database: \(error.localizedDescription)") }
        }
    }

    private var lastHealedDate: Date?

    func performLibraryHeal() async throws {
        let isAsleep = await SleepManager.shared.isAsleep
        guard !isAsleep else { return }
        if let lastHealed = lastHealedDate, Date().timeIntervalSince(lastHealed) < 300 {
            AppLogger.debug("⏭️ Skipping library heal — last heal was \(Int(Date().timeIntervalSince(lastHealed)))s ago", logger: AppLogger.background)
            return
        }
        lastHealedDate = Date()

        // 1. Repair Orphaned Entities
        try await repairOrphanedEntities()
        
        // 1.5. Purge stale search cache entries (older than 7 days)
        await purgeStaleSearchCache()

        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = MediaItem.thumbnailProperties
        descriptor.fetchLimit = 100
        
        var offset = 0
        var processedCount = 0
        var hasMore = true
        
        while hasMore {
            descriptor.fetchOffset = offset
            let items = try modelContext.fetch(descriptor)
            hasMore = items.count == 100
            
            // 2. Deduplicate and Standardize
            for item in items {
            if Task.isCancelled { break }
            if isThermalThrottled {
                AppLogger.warning("🌡️ Thermal throttle during library heal. Stopping early.", logger: AppLogger.background)
                hasMore = false
                break
            }
            // Migrate legacy IDs
            if !item.id.contains("_") {
                let typePrefix = item.type == .movie ? "movie" : "tv"
                item.id = "\(typePrefix)_\(item.id)"
            }

            if let tmdbIDString = item.id.split(separator: "_").last, let tmdbID = Int(tmdbIDString) {
                if let tv = item.tvShowDetails {
                    // 0. Reattach any orphaned seasons (tvShowDetails == nil) to this show,
                    // so imported/restored shows don't end up with empty season lists.
                    let orphanDesc = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID == tmdbID })
                    if let candidates = try? modelContext.fetch(orphanDesc) {
                        let orphans = candidates.filter { $0.tvShowDetails == nil }
                        if !orphans.isEmpty {
                            for season in orphans {
                                season.tvShowDetails = tv
                            }
                            AppLogger.info("🔗 Reattached \(orphans.count) orphaned seasons for \(item.title)", logger: AppLogger.background)
                        }
                    }

                    // 1. Standardize Seasons and Episodes first
                    let liveSeasons = tv.seasons.liveModels
                    for season in liveSeasons {
                        season.showID = tmdbID
                        if season.uniqueID == nil {
                            season.uniqueID = "\(tmdbID)_\(season.seasonNumber)"
                        }
                        
                        let liveEps = season.episodes.liveModels
                        for episode in liveEps {
                            episode.showID = tmdbID
                            if episode.uniqueID == nil {
                                episode.uniqueID = "\(tmdbID)_\(season.seasonNumber)_\(episode.episodeNumber)"
                            }
                            if episode.airDateValue == nil {
                                episode.updateAirDateValue()
                            }
                        }
                    }

                    // 2. Auto-mark unwatched episodes if Completed
                    let autoMark = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoMarkEpisodesWatched.rawValue)
                    if autoMark && item.stateValue == "Completed" {
                        let liveEps = liveSeasons.flatMap { $0.episodes.liveModels }
                        for ep in liveEps where !ep.isWatched {
                            ep.markWatched(true)
                        }
                    }

                    // 3. Refresh network info and creators from TMDB only if missing
                    let networkWasNil = tv.network == nil
                    let creatorsMissing = tv.creators.isEmpty
                    if tv.network == nil || tv.networkLogoPath == nil || creatorsMissing {
                        if let netDetails = try? await APIClient.shared.fetchTVDetails(tmdbID: tmdbID, force: false) {
                            if tv.network == nil { tv.network = netDetails.network }
                            if tv.networkLogoPath == nil { tv.networkLogoPath = netDetails.networkLogoPath }
                            if creatorsMissing { tv.creators = netDetails.creators.map { $0.name } }

                            // Episode gap detection: if TMDB reports more episodes than stored, trigger refresh
                            for seasonBrief in netDetails.seasons where seasonBrief.episode_count > 0 {
                                let sUID = "\(tmdbID)_\(seasonBrief.season_number)"
                                let sDesc = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.uniqueID == sUID })
                                if let existingSeason = try? modelContext.fetch(sDesc).first,
                                   existingSeason.episodes.count < seasonBrief.episode_count {
                                    _ = await self.refreshTVShow(id: item.id, tmdbID: tmdbID, metadataOnly: false, force: false)
                                    break
                                }
                            }
                        }
                    }
                    // If network was just populated, re-heal episode air dates
                    if networkWasNil && tv.network != nil {
                        for season in liveSeasons {
                            for episode in season.episodes.liveModels {
                                episode.updateAirDateValue()
                            }
                        }
                    }

                    // 4. Single recalculate at the end (was 3 separate calls)
                    tv.recalculateCachedProperties(triggerSync: true, force: true)

                    // 5. Heal: keep lastInteractionDate in sync with the most recent episode watch,
                    // so "Recently Watched" reflects real watch times.
                    if let latestWatch = liveSeasons
                        .flatMap({ $0.episodes.liveModels })
                        .compactMap({ $0.lastWatchedDate })
                        .max(),
                       latestWatch > (item.lastInteractionDate ?? .distantPast) {
                        item.lastInteractionDate = latestWatch
                    }
                }
            }
            
            item.syncCachedProperties(dirty: [.progress, .badge, .metadata, .cast])
            processedCount += 1
            }
            
            // Save after each batch
            if processedCount % 100 == 0 {
                await BadgeEngine.flushBadgeChanges(container: modelContext.container)
                try modelContext.save()
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms between batches
            }
            
            offset += 100
        }
        
        // Final save
        await BadgeEngine.flushBadgeChanges(container: modelContext.container)
        try modelContext.save()
        
        // Phase 7: Global Notification Resync
        // After healing metadata and cached properties, ensure the system notification queue is up to date.
        await NotificationManager.shared.scheduleAllUpcomingNotifications()
        
        // Full recount to fix any drift from concurrent onBadgeChanged tasks
        let sync = DiscoverySyncService(modelContainer: modelContext.container)
        await sync.syncLibrary(force: false)
        
        // Broadcast so UI refreshes with healed data
        await MainActor.run {
            MediaStateService.shared.postMediaStateChanged()
        }
        
        AppLogger.info("✅ Maintenance: Library heal complete.", logger: AppLogger.background)
    }

    /// One-time migration: rebuild `searchableText` so localized language names are searchable.
    func performSearchableLanguageMigration() async throws {
        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = MediaItem.thumbnailProperties
        descriptor.fetchLimit = 100

        var offset = 0
        var processedCount = 0
        var hasMore = true

        while hasMore {
            descriptor.fetchOffset = offset
            let items = try modelContext.fetch(descriptor)
            hasMore = items.count == 100

            for item in items {
                if Task.isCancelled { return }
                item.syncCachedProperties(dirty: .searchable)
            }

            processedCount += items.count
            try modelContext.save()
            offset += 100
            AppLogger.debug("♻️ Searchable language migration: \(processedCount) items processed", logger: AppLogger.background)
        }
    }

    private func repairOrphanedEntities() async throws {
        var allSeasons: [TVSeason] = []
        var offset = 0
        let batchSize = 500
        while true {
            var sDesc = FetchDescriptor<TVSeason>()
            sDesc.fetchLimit = batchSize
            sDesc.fetchOffset = offset
            let batch = try modelContext.fetch(sDesc)
            allSeasons.append(contentsOf: batch)
            if batch.count < batchSize { break }
            offset += batchSize
        }
        let tvDetailsDesc = FetchDescriptor<TVShowDetails>()
        let allTVDetails = try modelContext.fetch(tvDetailsDesc)

        // Group TVShowDetails by tmdbID to find duplicates
        var grouped: [Int: [TVShowDetails]] = [:]
        for details in allTVDetails {
            grouped[details.tmdbID, default: []].append(details)
        }

        var tvMap: [Int: TVShowDetails] = [:]
        for (tmdbID, duplicates) in grouped {
            if duplicates.count == 1 {
                tvMap[tmdbID] = duplicates[0]
                continue
            }

            // Multiple TVShowDetails for the same tmdbID — find the primary (most complete)
            AppLogger.warning("🔍 Found \(duplicates.count) TVShowDetails duplicates for tmdbID=\(tmdbID)", logger: AppLogger.background)

            // Score each duplicate: seasons, cast, item relationship
            var best: (index: Int, score: Int) = (0, 0)
            for (i, d) in duplicates.enumerated() {
                var score = 0
                let liveSeasons = d.seasons.liveModels
                score += liveSeasons.count * 10
                score += d.cast.liveModels.count * 5
                if d.nextEpisodeDate != nil { score += 3 }
                if d.status != nil { score += 1 }

                // Confirm item relationship via direct fetch (not relying on faulting)
                if let context = d.modelContext {
                    let itemDesc = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == "tv_\(tmdbID)" || $0.id == "\(tmdbID)" })
                    if let item = try? context.fetch(itemDesc).first {
                        // Verify the relationship points back
                        if item.tvShowDetails?.persistentModelID == d.persistentModelID {
                            score += 50
                        }
                    }
                }

                if score > best.score {
                    best = (i, score)
                }
            }

            let primary = duplicates[best.index]
            tvMap[tmdbID] = primary

            // Merge data from secondary duplicates into primary, then delete secondaries
            for (i, secondary) in duplicates.enumerated() where i != best.index {
                let liveSeasons = secondary.seasons.liveModels
                for season in liveSeasons {
                    if season.tvShowDetails?.persistentModelID != primary.persistentModelID {
                        season.tvShowDetails = primary
                    }
                    if !primary.seasons.contains(where: { $0.persistentModelID == season.persistentModelID }) {
                        primary.seasons.append(season)
                    }
                }

                let liveCast = secondary.cast.liveModels
                for member in liveCast {
                    if member.tvShowDetails?.persistentModelID != primary.persistentModelID {
                        member.tvShowDetails = primary
                    }
                }

                // Transfer item relationship if primary doesn't have one
                if primary.item == nil, let attachedItem = secondary.item {
                    attachedItem.tvShowDetails = primary
                }

                modelContext.delete(secondary)
                AppLogger.info("🧹 Merged and deleted duplicate TVShowDetails for tmdbID=\(tmdbID)", logger: AppLogger.background)
            }
        }

        for season in allSeasons {
            if season.tvShowDetails == nil, let showID = season.showID, let parent = tvMap[showID] {
                season.tvShowDetails = parent
            }
        }

        var allEpisodes: [TVEpisode] = []
        var epOffset = 0
        while true {
            var eDesc = FetchDescriptor<TVEpisode>()
            eDesc.fetchLimit = batchSize
            eDesc.fetchOffset = epOffset
            let batch = try modelContext.fetch(eDesc)
            allEpisodes.append(contentsOf: batch)
            if batch.count < batchSize { break }
            epOffset += batchSize
        }

        var seasonMap: [Int: [Int: TVSeason]] = [:]
        for season in allSeasons {
            guard let showID = season.showID else { continue }
            if seasonMap[showID] == nil { seasonMap[showID] = [:] }
            seasonMap[showID]?[season.seasonNumber] = season
        }

        for episode in allEpisodes {
            if episode.season == nil, let showID = episode.showID, let parentSeason = seasonMap[showID]?[episode.seasonNumber] {
                episode.season = parentSeason
            }
        }
    }
    
    private func purgeStaleSearchCache() async {
        let sevenDaysAgo = Date().addingTimeInterval(-.days7)
        let descriptor = FetchDescriptor<SearchCacheEntity>(
            predicate: #Predicate { $0.timestamp < sevenDaysAgo }
        )
        if let staleEntries = try? modelContext.fetch(descriptor), !staleEntries.isEmpty {
            for entry in staleEntries {
                modelContext.delete(entry)
            }
            try? modelContext.save()
            AppLogger.info("🧹 Purged \(staleEntries.count) stale search cache entries", logger: AppLogger.background)
        }
    }

    func refreshMetadata(for itemIDs: [String], metadataOnly: Bool = false, force: Bool = false) async {
        if isThermalThrottled {
            AppLogger.warning("🌡️ Thermal state serious or Low Power Mode active. Skipping background refresh.", logger: AppLogger.background)
            return
        }

        var errorCount = 0
        var refreshedIDs: [String] = []

        // Phase 2 Optimization: Controlled concurrent network calls.
        // The @ModelActor serializes model context writes, but the async network
        // calls inside refreshSingleItem release the actor, allowing other tasks
        // to make progress. This gives us parallel network I/O with safe serial writes.
        let maxConcurrent = 8
        await withTaskGroup(of: (Int, Bool).self) { group in
            var submitted = 0

            for (index, id) in itemIDs.prefix(maxConcurrent).enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return (index, false) }
                    let ok = await self.refreshSingleItem(id: id, metadataOnly: metadataOnly, force: force, shouldSave: false)
                    return (index, ok)
                }
                submitted += 1
            }

            for await (index, success) in group {
                if success {
                    refreshedIDs.append(itemIDs[index])
                } else {
                    errorCount += 1
                }

                // Check thermal state mid-batch to prevent overheating during large refreshes
                if isThermalThrottled {
                    AppLogger.warning("🌡️ Thermal throttle detected mid-batch. Aborting remaining refreshes.", logger: AppLogger.background)
                    break
                }

                if submitted < itemIDs.count {
                    let nextIndex = submitted
                    group.addTask { [weak self] in
                        guard let self else { return (nextIndex, false) }
                        let ok = await self.refreshSingleItem(id: itemIDs[nextIndex], metadataOnly: metadataOnly, force: force, shouldSave: false)
                        return (nextIndex, ok)
                    }
                    submitted += 1
                }
            }
        }

        // Flush buffered badge changes before the batch save
        await BadgeEngine.flushBadgeChanges(container: modelContext.container)

        // Phase 2 Optimization: Batch Save with Robust Error Handling
        do {
            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            Task { @MainActor in AppErrorState.shared.surfaceError("Background refresh save failed: \(error.localizedDescription)") }
        }
        
        // Phase 5: Bulk Notification
        if !refreshedIDs.isEmpty {
            Task { @MainActor in
                MediaStateService.shared.postBulkRefreshed()
            }
        }
        
        AppLogger.info("✅ Background Refresh: Completed with \(errorCount) errors.", logger: AppLogger.background)
    }

    func refreshSingleItem(id: String, metadataOnly: Bool = false, force: Bool = false, shouldSave: Bool = true) async -> Bool {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return false }
        
        let tmdbIDString = item.id.split(separator: "_").last ?? item.id[...]
        guard let tmdbID = Int(tmdbIDString) else { return false }

        do {
            let itemType = item.type
            // Deduplication handled by APIClient in-flight coalescing (inFlightMovieDetails/TVDetails)
            // — no need for SyncCoordinator which would capture self (non-Sendable) into a @Sendable closure.
            let success: Bool
            if itemType == .movie {
                success = await self.refreshMovie(id: id, tmdbID: tmdbID, force: force)
            } else if itemType == .tvShow {
                success = await self.refreshTVShow(id: id, tmdbID: tmdbID, metadataOnly: metadataOnly, force: force)
            } else {
                success = false
            }
            if !success { return false }
            
            // Phase 5: Notification Scheduling (skip in tests)
            if NSClassFromString("XCTest") == nil {
                if item.type == .movie {
                    let identifier = "movie-\(item.id)"
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(identifier)-day1", "\(identifier)-day2"])
                    
                    await NotificationManager.shared.scheduleMovieNotification(
                        id: item.id, 
                        title: item.title, 
                        releaseDate: item.releaseDate, 
                        posterURL: item.posterURL
                    )
                } else if item.type == .tvShow, let tv = item.tvShowDetails {
                    let identifier = "tv-\(item.id)"
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(identifier)-day1", "\(identifier)-day2"])
                    
                    await NotificationManager.shared.scheduleTVNotification(
                        id: item.id, 
                        title: item.title, 
                        posterURL: item.posterURL, 
                        nextDate: tv.nextEpisodeDate, 
                        nextEpisodeNumber: tv.nextEpisodeNumber, 
                        nextSeasonNumber: tv.nextSeasonNumber, 
                        nextEpisodeTime: nil
                    )
                }
            }

            if shouldSave {
                try modelContext.save()
                let refreshedID = item.id
                let refreshedPID = item.persistentModelID
                Task { @MainActor in
                    MediaStateService.shared.postItemRefreshed(id: refreshedID, persistentID: refreshedPID)
                }
            }
            return true
        } catch {
            let title = item.title
            Task { @MainActor in AppErrorState.shared.surfaceError("Failed to refresh \(title): \(error.localizedDescription)") }
            return false
        }
    }

    func markAllEpisodesAsWatched(itemID: String) async {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        
        let tmdbIDString = item.id.split(separator: "_").last ?? item.id[...]
        guard let tmdbID = Int(tmdbIDString) else { return }

        // 1. Force refresh TMDB details first to get the latest list of seasons and episodes
        _ = await refreshTVShow(id: itemID, tmdbID: tmdbID, metadataOnly: false, force: true)
        
        // Refetch the item to ensure context alignment
        guard let refreshedItem = try? modelContext.fetch(descriptor).first,
              let tv = refreshedItem.tvShowDetails else { return }
              
        // 2. Fetch and pre-populate missing episodes for seasons if needed
        let sDescriptor = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID == tmdbID })
        if let seasons = try? modelContext.fetch(sDescriptor) {
            let liveSeasons = seasons.liveModels
            
            // N+1 Prevention: Prefetch all episodes for this show into a map
            let eDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.showID == tmdbID })
            let allEpisodes = (try? modelContext.fetch(eDescriptor)) ?? []
            var episodeMap = Dictionary(uniqueKeysWithValues: allEpisodes.compactMap { ep -> (String, TVEpisode)? in
                guard let uid = ep.uniqueID else { return nil }
                return (uid, ep)
            })
            
            // Fetch TVMaze once so each season can fill missing TMDB runtimes and
            // add valid episode rows that TMDB has not returned yet.
            let mazeId = tv.tvMazeID
            let mazeAll: [TVMazeEpisode] = (mazeId != nil && mazeId! > 0) ? (try? await APIClient.shared.fetchTVMazeEpisodes(tvMazeID: mazeId!, force: false)) ?? [] : []
            let mazeRawBySeason: [Int: [TVMazeEpisode]] = {
                var d: [Int: [TVMazeEpisode]] = [:]
                for ep in mazeAll { if let s = ep.season, s > 0 { d[s, default: []].append(ep) } }
                for (k,v) in d { d[k] = v.sorted { ($0.number ?? 0) < ($1.number ?? 0) } }
                return d
            }()

            // Concurrent Fetching: Pre-fetch all missing season details in parallel to avoid sequential network bottleneck
            var results: [Int: [TVEpisodeResult]] = [:]
            await withTaskGroup(of: (Int, Result<[TVEpisodeResult], Error>).self) { group in
                for season in liveSeasons {
                    let sNum = season.seasonNumber
                    if season.episodes.isEmpty || season.episodes.count < season.episodeCount {
                        group.addTask {
                            do {
                                let eps = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum)
                                return (sNum, .success(eps))
                            } catch {
                                return (sNum, .failure(error))
                            }
                        }
                    }
                }
                
                for await (sNum, res) in group {
                    switch res {
                    case .success(let eps):
                        results[sNum] = eps
                    case .failure(let error):
                        AppLogger.warning("⚠️ Failed to download details for season \(sNum) during auto-completion: \(error)", logger: AppLogger.background)
                    }
                }
            }
            
            for season in liveSeasons {
                if isThermalThrottled {
                    AppLogger.warning("🌡️ Thermal throttle during episode marking. Stopping early.", logger: AppLogger.background)
                    break
                }
                if season.tvShowDetails?.persistentModelID != tv.persistentModelID {
                    season.tvShowDetails = tv
                }
                
                let sNum = season.seasonNumber
                // If season has no episodes, or is missing some, fetch and populate
                if season.episodes.isEmpty || season.episodes.count < season.episodeCount {
                    if let tmdbEpisodes = results[sNum] {
                        let tvmazeRawForSeason = mazeRawBySeason[sNum] ?? []
                        let runtimeMap = RuntimeFallback.runtimeMap(
                            tmdbEpisodes: tmdbEpisodes,
                            tvmazeSeason: tvmazeRawForSeason
                        )
                        for ep in tmdbEpisodes {
                            let epUniqueID = "\(tmdbID)_\(sNum)_\(ep.episodeNumber)"
                            let epName = ep.name ?? "Episode \(ep.episodeNumber)"
                            let epOverview = ep.overview ?? ""
                            let runtime = runtimeMap[ep.episodeNumber] ?? ep.runtime
                            let episode: TVEpisode
                            if let existing = episodeMap[epUniqueID] {
                                episode = existing
                                episode.name = epName
                                episode.overview = epOverview
                                episode.airDate = ep.airDate
                                episode.runtime = runtime
                                episode.updateAirDateValue()
                            } else {
                                episode = TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: epName, overview: epOverview, airDate: ep.airDate, airstamp: nil, runtime: runtime, showID: tmdbID)
                                episode.showID = tmdbID
                                modelContext.insert(episode)
                                episodeMap[epUniqueID] = episode
                            }
                             
                            if episode.season?.persistentModelID != season.persistentModelID {
                                episode.season = season
                            }
                            episode.markWatched(true)
                        }
                        let existingNumbers = Set(tmdbEpisodes.map(\.episodeNumber))
                        let extras = RuntimeFallback.validExtras(
                            tmdbEpisodeNumbers: existingNumbers,
                            tvmazeSeason: tvmazeRawForSeason
                        )
                        if !extras.isEmpty {
                            for mazeEp in extras {
                                guard let n = mazeEp.number else { continue }
                                let uid = "\(tmdbID)_\(sNum)_\(n)"
                                if episodeMap[uid] != nil { continue }
                                let ep = TVEpisode(episodeNumber: n, seasonNumber: sNum, name: mazeEp.name ?? "Episode \(n)", overview: mazeEp.summary?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) ?? "", airDate: mazeEp.airdate, airstamp: mazeEp.airstamp, runtime: mazeEp.runtime, showID: tmdbID)
                                ep.showID = tmdbID
                                ep.season = season
                                modelContext.insert(ep)
                                episodeMap[uid] = ep
                                ep.markWatched(true)
                            }
                            season.episodeCount = max(season.episodeCount, season.episodes.count)
                        }
                    }
                } else {
                    for episode in season.episodes {
                        episode.markWatched(true)
                    }
                }
            }
        }
        
        tv.recalculateCachedProperties(triggerSync: true, force: true)
        refreshedItem.lastInteractionDate = Date()
        refreshedItem.syncCachedProperties(dirty: .all)
        
        // Invalidate badge scan cache since episodes changed
        BadgeEngine.invalidateScan(for: refreshedItem.persistentModelID)
        
        do {
            await BadgeEngine.flushBadgeChanges(container: modelContext.container)
            try modelContext.save()
            AppLogger.info("✅ Deep Completion: Marked all episodes as watched for \(itemID).", logger: AppLogger.background)
            
            // Broadcast the refresh
            let refreshedPID = refreshedItem.persistentModelID
            await MainActor.run {
                MediaStateService.shared.postItemRefreshed(id: itemID, persistentID: refreshedPID)
            }
        } catch {
            Task { @MainActor in AppErrorState.shared.surfaceError("Failed to complete show: \(error.localizedDescription)") }
        }
    }

}
