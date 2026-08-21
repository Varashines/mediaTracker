import Foundation
import SwiftData
import UserNotifications
import AppKit

@ModelActor
actor BackgroundDataService {
    var isThermalThrottled: Bool {
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

    var lastHealedDate: Date?


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
