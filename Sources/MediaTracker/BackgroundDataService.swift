import Foundation
import SwiftData
import UserNotifications
import AppKit

@ModelActor
actor BackgroundDataService {
    private let decoder = JSONDecoder()

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

        // 3. Fetch full details immediately
        if type == .movie {
            _ = await self.refreshMovie(id: uniqueID, tmdbID: tmdbID)
        } else if type == .tvShow {
            _ = await self.refreshTVShow(id: uniqueID, tmdbID: tmdbID)
        }
        
        item.syncCachedProperties(force: true)
        item.updateSearchableText()
        try? modelContext.save()
        return (item.persistentModelID, false)
    }

    func importLibraryData(backup: LibraryBackup) async -> Int {
        let descriptor = FetchDescriptor<MediaItem>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingKeys = Set(existing.map { "\($0.id)_\($0.type?.rawValue ?? "")" })
        
        var importedCount = 0
        for itemData in backup.items {
            let typePrefix = itemData.type.lowercased().contains("movie") ? "movie" : "tv"
            let tmdbIDPart = itemData.id.split(separator: "_").last ?? itemData.id[...]
            let uniqueID = "\(typePrefix)_\(tmdbIDPart)"
            let key = "\(uniqueID)_\(itemData.type)"
            
            if !existingKeys.contains(key) {
                let item = MediaItem(
                    id: uniqueID,
                    title: itemData.title,
                    overview: "",
                    posterURL: nil,
                    releaseDate: nil,
                    type: MediaType(rawValue: itemData.type) ?? .movie
                )
                item.state = MediaState(rawValue: itemData.state) ?? .wishlist
                item.dateAdded = itemData.dateAdded
                item.tasteValue = itemData.taste ?? TasteValue.none.rawValue
                modelContext.insert(item)
                importedCount += 1

                // Restore Episode Progress
                if item.type == .tvShow, let watchedIDs = itemData.watchedEpisodeIDs, let tmdbID = Int(tmdbIDPart) {
                    for epID in watchedIDs {
                        // epID format: "tmdbID_season_episode"
                        let parts = epID.split(separator: "_")
                        if parts.count == 3, 
                           let sNum = Int(parts[1]), 
                           let eNum = Int(parts[2]) {
                            
                            let epUniqueID = "\(tmdbID)_\(sNum)_\(eNum)"
                            // Skip if episode already exists (uniqueID collision)
                            let existingDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.uniqueID == epUniqueID })
                            if let existing = try? modelContext.fetch(existingDescriptor).first, existing.modelContext != nil {
                                continue
                            }
                            
                            let stubEpisode = TVEpisode(
                                episodeNumber: eNum, 
                                seasonNumber: sNum, 
                                name: "Episode \(eNum)", 
                                overview: "", 
                                airDate: nil, 
                                runtime: nil, 
                                isWatched: true,
                                showID: tmdbID
                            )
                            stubEpisode.uniqueID = epUniqueID
                            modelContext.insert(stubEpisode)
                            // The background sync will later link these to seasons and details via uniqueID
                        }
                    }
                }
            }
        }
        
        try? modelContext.save()
        return importedCount
    }

    func deleteMediaItem(id: String) async {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        
        let posterURL = item.posterURL
        let backdropURL = item.backdropURL
        
        modelContext.delete(item)
        
        do {
            try modelContext.save()
            AppLogger.info("🗑️ Cascade Deletion: Deleted \(id) and all associated records.", logger: AppLogger.background)
        } catch {
            Task { @MainActor in AppErrorState.shared.surfaceError("Failed to delete item: \(error.localizedDescription)") }
        }
        
        await ImageCache.shared.removeImage(forKey: posterURL)
        await ImageCache.shared.removeImage(forKey: backdropURL)
    }

    func clearDatabase() async {
        do {
            try modelContext.delete(model: MediaItem.self)
            try modelContext.delete(model: NetworkEntity.self)
            try modelContext.delete(model: GenreEntity.self)
            try modelContext.delete(model: LanguageEntity.self)
            try modelContext.delete(model: MediaCollection.self)
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
        if let lastHealed = lastHealedDate, Date().timeIntervalSince(lastHealed) < 300 {
            AppLogger.debug("⏭️ Skipping library heal — last heal was \(Int(Date().timeIntervalSince(lastHealed)))s ago", logger: AppLogger.background)
            return
        }
        lastHealedDate = Date()

        // 1. Repair Orphaned Entities
        try await repairOrphanedEntities()
        
        // 1.5. Purge stale search cache entries (older than 7 days)
        await purgeStaleSearchCache()

        let descriptor = FetchDescriptor<MediaItem>()
        let items = try modelContext.fetch(descriptor)
        
        // 2. Deduplicate and Standardize
        for item in items {
            await Task.yield()
            
            // Migrate legacy IDs
            if !item.id.contains("_") {
                let typePrefix = item.type == .movie ? "movie" : "tv"
                item.id = "\(typePrefix)_\(item.id)"
            }

            if let tmdbIDString = item.id.split(separator: "_").last, let tmdbID = Int(tmdbIDString) {
                if let tv = item.tvShowDetails {
                    // Force Watch State Consistency (only if auto-mark is enabled)
                    let autoMark = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoMarkEpisodesWatched.rawValue)
                    if autoMark && item.stateValue == "Completed" {
                        // Defensive: skip deleted/detached during concurrent merges
                        let liveEps = tv.seasons
                            .liveModels
                            .flatMap { $0.episodes.liveModels }
                        for ep in liveEps where !ep.isWatched {
                            ep.markWatched(true)
                        }
                    }

                    // Standardize Seasons and Episodes
                    // Defensive: skip deleted/detached seasons and episodes
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
                    tv.recalculateCachedProperties(triggerSync: true, force: true)
                }
            }
            
            item.syncCachedProperties(force: true)
            item.updateSearchableText()
        }
        
        try modelContext.save()
        
        // Phase 7: Global Notification Resync
        // After healing metadata and cached properties, ensure the system notification queue is up to date.
        await NotificationManager.shared.scheduleAllUpcomingNotifications()
        
        AppLogger.info("✅ Maintenance: Library heal complete.", logger: AppLogger.background)
    }

    private func repairOrphanedEntities() async throws {
        let sDesc = FetchDescriptor<TVSeason>()
        let allSeasons = try modelContext.fetch(sDesc)
        let tvDetailsDesc = FetchDescriptor<TVShowDetails>()
        let allTVDetails = try modelContext.fetch(tvDetailsDesc)
        
        // Fix for Crash: Safely handle duplicate tmdbIDs if they exist in the DB
        let tvMap = Dictionary(allTVDetails.map { ($0.tmdbID, $0) }, uniquingKeysWith: { first, second in
            // Logic to keep the one that actually has a MediaItem attached
            if first.item != nil { 
                if second.item == nil {
                    modelContext.delete(second) // Clean up the orphaned duplicate
                }
                return first 
            }
            if second.item != nil { 
                modelContext.delete(first) // Clean up the orphaned duplicate
                return second 
            }
            return first
        })
        
        for season in allSeasons {
            if season.tvShowDetails == nil, let showID = season.showID, let parent = tvMap[showID] {
                season.tvShowDetails = parent
            }
        }
        
        let eDesc = FetchDescriptor<TVEpisode>()
        let allEpisodes = try modelContext.fetch(eDesc)
        
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
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)
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

    func deepHealGenres() async {
        let descriptor = FetchDescriptor<MediaItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }
        
        AppLogger.info("🧬 Deep Heal: Starting genre deconstruction for \(items.count) items...", logger: AppLogger.background)
        
        for item in items {
            item.syncCachedProperties(force: true)
            item.updateSearchableText()
        }
        
        do {
            try modelContext.save()
                AppLogger.info("✅ Deep Heal: Genre deconstruction complete.", logger: AppLogger.background)
            
            // Re-sync discovery entities to reflect new atomic genres
            let sync = DiscoverySyncService(modelContainer: modelContext.container)
            await sync.syncLibrary(force: true)
            
            await MainActor.run {
                MediaStateService.shared.postMediaStateChanged()
            }
        } catch {
            Task { @MainActor in AppErrorState.shared.surfaceError("Library heal failed to save: \(error.localizedDescription)") }
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
        let maxConcurrent = 4
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
            // Phase 1: Wrap the entire refresh logic in the SyncCoordinator to prevent race conditions.
            let success = try await SyncCoordinator.shared.perform(key: "sync_\(tmdbID)") {
                let success: Bool
                if itemType == .movie {
                    success = await self.refreshMovie(id: id, tmdbID: tmdbID, force: force)
                } else if itemType == .tvShow {
                    success = await self.refreshTVShow(id: id, tmdbID: tmdbID, metadataOnly: metadataOnly, force: force)
                } else {
                    success = false
                }
                return success
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
                if season.tvShowDetails?.persistentModelID != tv.persistentModelID {
                    season.tvShowDetails = tv
                }
                
                let sNum = season.seasonNumber
                // If season has no episodes, or is missing some, fetch and populate
                if season.episodes.isEmpty || season.episodes.count < season.episodeCount {
                    if let tmdbEpisodes = results[sNum] {
                        for ep in tmdbEpisodes {
                            let epUniqueID = "\(tmdbID)_\(sNum)_\(ep.episodeNumber)"
                            let epName = ep.name ?? "Episode \(ep.episodeNumber)"
                            let epOverview = ep.overview ?? ""
                            
                            let episode: TVEpisode
                            if let existing = episodeMap[epUniqueID] {
                                episode = existing
                                episode.name = epName
                                episode.overview = epOverview
                                episode.airDate = ep.airDate
                                episode.runtime = ep.runtime
                                episode.updateAirDateValue()
                            } else {
                                episode = TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: epName, overview: epOverview, airDate: ep.airDate, airstamp: nil, runtime: ep.runtime, showID: tmdbID)
                                episode.showID = tmdbID
                                modelContext.insert(episode)
                                episodeMap[epUniqueID] = episode
                            }
                            
                            if episode.season?.persistentModelID != season.persistentModelID {
                                episode.season = season
                            }
                            episode.markWatched(true)
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
        refreshedItem.syncCachedProperties(force: true)
        refreshedItem.updateSearchableText()
        refreshedItem.checkOverallCompletion()
        
        do {
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
