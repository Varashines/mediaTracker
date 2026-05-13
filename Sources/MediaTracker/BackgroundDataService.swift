import Foundation
import SwiftData
import UserNotifications

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
                item.tasteValue = itemData.taste ?? "None"
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
        
        modelContext.delete(item)
        
        do {
            try modelContext.save()
            print("🗑️ Cascade Deletion: Deleted \(id) and all associated records.")
        } catch {
            print("❌ Cascade Deletion: Failed to save deletion: \(error)")
        }
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
            
            print("✅ Database cleared successfully.")
        } catch {
            print("❌ Failed to clear database: \(error.localizedDescription)")
        }
    }

    func performLibraryHeal() async throws {
        // 1. Repair Orphaned Entities
        try await repairOrphanedEntities()

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
                    // Force Watch State Consistency
                    if item.stateValue == "Completed" {
                        let episodes = tv.seasons.flatMap { $0.episodes }
                        for ep in episodes where !ep.isWatched {
                            ep.isWatched = true
                        }
                    }

                    // Standardize Seasons and Episodes
                    for season in tv.seasons {
                        season.showID = tmdbID
                        if season.uniqueID == nil {
                            season.uniqueID = "\(tmdbID)_\(season.seasonNumber)"
                        }
                        
                        for episode in season.episodes {
                            episode.showID = tmdbID
                            if episode.uniqueID == nil {
                                episode.uniqueID = "\(tmdbID)_\(season.seasonNumber)_\(episode.episodeNumber)"
                            }
                            if episode.airDateValue == nil {
                                episode.updateAirDateValue()
                            }
                        }
                    }
                    tv.recalculateCachedProperties(triggerSync: true)
                }
            }
            
            item.syncCachedProperties()
            item.updateSearchableText()
        }
        
        try modelContext.save()
        
        // Phase 7: Global Notification Resync
        // After healing metadata and cached properties, ensure the system notification queue is up to date.
        await NotificationManager.shared.scheduleAllUpcomingNotifications()
        
        print("✅ Maintenance: Library heal complete.")
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

    func refreshMetadata(for itemIDs: [String], metadataOnly: Bool = false, force: Bool = false) async {
        if isThermalThrottled {
            print("🌡️ Thermal state serious or Low Power Mode active. Skipping background refresh.")
            return
        }
        
        var errorCount = 0
        var refreshedIDs: [String] = []

        // Phase 5 Optimization: Serial Processing for Context Integrity
        // While fetching in parallel is possible, applying updates to the same ModelContext
        // from multiple tasks within a TaskGroup is unsafe. We serialize updates to guarantee integrity.
        for id in itemIDs {
            let success = await self.refreshSingleItem(id: id, metadataOnly: metadataOnly, force: force, shouldSave: false)
            if success {
                refreshedIDs.append(id)
            } else {
                errorCount += 1
            }
        }

        // Phase 2 Optimization: Batch Save with Robust Error Handling
        do {
            if modelContext.hasChanges {
                try modelContext.save()
            }
        } catch {
            print("❌ Background Refresh: Failed to save batch context: \(error)")
        }
        
        // Phase 5: Bulk Notification
        if !refreshedIDs.isEmpty {
            let ids = refreshedIDs
            Task { @MainActor in
                NotificationCenter.default.post(name: .mediaItemsBulkRefreshed, object: nil, userInfo: ["ids": ids])
            }
        }
        
        print("✅ Background Refresh: Completed with \(errorCount) errors.")
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
            
            item.syncCachedProperties()
            item.updateSearchableText()
            
            // Phase 5: Notification Scheduling
            if item.type == .movie {
                // Clear old notifications before scheduling updated ones
                let identifier = "movie-\(item.id)"
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["\(identifier)-day1", "\(identifier)-day2"])
                
                await NotificationManager.shared.scheduleMovieNotification(
                    id: item.id, 
                    title: item.title, 
                    releaseDate: item.releaseDate, 
                    posterURL: item.posterURL
                )
            } else if item.type == .tvShow, let tv = item.tvShowDetails {
                // Clear old notifications before scheduling updated ones
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

            if shouldSave {
                try modelContext.save()
                let refreshedID = item.id
                Task { @MainActor in
                    NotificationCenter.default.post(name: .mediaItemRefreshed, object: nil, userInfo: ["id": refreshedID])
                }
            }
            return true
        } catch {
            print("❌ Refresh error for \(item.title): \(error)")
            return false
        }
    }

    func markAllEpisodesAsWatched(itemID: String) async {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == itemID })
        guard let item = try? modelContext.fetch(descriptor).first else { return }
        
        let tmdbIDString = item.id.split(separator: "_").last ?? item.id[...]
        guard let tmdbID = Int(tmdbIDString) else { return }

        // Deep Heal: Ensure all records are linked before updating
        if let tv = item.tvShowDetails {
            let sDescriptor = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID == tmdbID })
            if let seasons = try? modelContext.fetch(sDescriptor) {
                for season in seasons {
                    if season.tvShowDetails?.persistentModelID != tv.persistentModelID {
                        season.tvShowDetails = tv
                    }
                    
                    let sNum = season.seasonNumber
                    let eDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.showID == tmdbID && $0.seasonNumber == sNum })
                    if let episodes = try? modelContext.fetch(eDescriptor) {
                        for episode in episodes {
                            if episode.season?.persistentModelID != season.persistentModelID {
                                episode.season = season
                            }
                            episode.markWatched(true)
                        }
                    }
                }
            }
            tv.recalculateCachedProperties(triggerSync: true)
        }
        
        item.lastInteractionDate = Date()
        item.syncCachedProperties()
        item.updateSearchableText()
        item.checkOverallCompletion()
        
        do {
            try modelContext.save()
            print("✅ Deep Completion: Marked all episodes as watched for \(itemID).")
        } catch {
            print("❌ Deep Completion: Failed to save: \(error)")
        }
    }

    private func refreshMovie(id: String, tmdbID: Int, force: Bool = false) async -> Bool {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return false }
        
        do {
            let details = try await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID, force: force)
            item.releaseDate = DateUtils.parseDate(details.releaseDate)
            if let newOverview = details.overview {
                item.overview = newOverview
            }
            
            item.posterURL = APIClient.tmdbImageURL(path: details.posterPath) ?? item.posterURL
            item.backdropURL = APIClient.tmdbImageURL(path: details.backdropPath, size: "w780")
            
            let movieDetails = item.movieDetails ?? MovieDetails(tmdbID: tmdbID)
            movieDetails.item = item
            item.movieDetails = movieDetails
            movieDetails.runtime = details.runtime
            movieDetails.genres = details.genres
            movieDetails.voteAverage = details.voteAverage
            movieDetails.originalLanguage = await StringPool.shared.intern(details.originalLanguage)
            movieDetails.creators = details.directors.map { $0.name }
            
            // Update Cast
            let newCastResults = details.cast
            let currentCast = item.displayCast
            let hasChanged = currentCast.count != newCastResults.count || 
                            zip(currentCast.sorted(by: { $0.name < $1.name }), 
                                newCastResults.sorted(by: { $0.name < $1.name }))
                            .contains(where: { $0.0.name != $0.1.name || $0.0.characterName != $0.1.character })

            if hasChanged || movieDetails.cast.isEmpty {
                movieDetails.cast.forEach { modelContext.delete($0) }
                
                var seen = Set<String>()
                var newCastList: [CastMember] = []
                for c in newCastResults {
                    if seen.contains(c.name) { continue }
                    seen.insert(c.name)
                    
                    let profileURL = APIClient.tmdbImageURL(path: c.profilePath, size: "w185")
                    let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order, mediaID: item.id)
                    member.movieDetails = movieDetails
                    modelContext.insert(member)
                    newCastList.append(member)
                }
                movieDetails.cast = newCastList
            }
            
            if movieDetails.modelContext == nil { modelContext.insert(movieDetails) }
            item.lastUpdated = Date()
            return true
        } catch {
            return false
        }
    }

    private func refreshTVShow(id: String, tmdbID: Int, metadataOnly: Bool = false, force: Bool = false) async -> Bool {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return false }

        do {
            let details = try await APIClient.shared.fetchTVDetails(tmdbID: tmdbID, force: force)
            let tvDetails = item.tvShowDetails ?? TVShowDetails(tmdbID: tmdbID)
            tvDetails.item = item
            item.tvShowDetails = tvDetails
            
            let totalCachedEpisodes = tvDetails.seasons.reduce(0) { $0 + $1.episodes.count }
            let hasMissingEpisodes = tvDetails.seasons.contains(where: { $0.episodes.isEmpty }) && !tvDetails.seasons.isEmpty
            
            if let newDate = DateUtils.parseDate(details.firstAirDate) {
                item.releaseDate = newDate
            }
            if let newOverview = details.overview {
                item.overview = newOverview
            }
            
            item.posterURL = APIClient.tmdbImageURL(path: details.posterPath) ?? item.posterURL
            item.backdropURL = APIClient.tmdbImageURL(path: details.backdropPath, size: "w780")
            
            // Initialize next episode fields with TMDB data as baseline
            tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
            tvDetails.nextSeasonNumber = details.nextSeasonNumber
            if let tmdbNextDate = details.nextEpisodeDate {
                tvDetails.nextEpisodeDate = DateUtils.parseDate(tmdbNextDate)
            }
            
            var tvMazeID = tvDetails.tvMazeID
            if let tvdbID = details.tvdbID, tvMazeID == nil {
                tvMazeID = try? await APIClient.shared.lookupTVMazeID(tvdbID: tvdbID)
            }
            
            var mazeEpisodes: [TVMazeEpisode] = []
            if let mID = tvMazeID {
                if let (episode, timezone, service, airtime) = try? await APIClient.shared.fetchTVMazeSchedule(tvMazeID: mID) {
                    tvDetails.timezone = timezone
                    tvDetails.nextEpisodeTime = airtime
                    
                    if let schedule = episode {
                        tvDetails.nextEpisodeDate = DateUtils.parseFullDate(dateString: schedule.airdate, timeString: schedule.airtime, airstamp: schedule.airstamp, timezone: timezone, serviceName: service, item: item)
                        
                        // Sync episode/season from TVMaze to match the more accurate date
                        if let sNum = schedule.season { tvDetails.nextSeasonNumber = sNum }
                        if let eNum = schedule.number { tvDetails.nextEpisodeNumber = eNum }
                    }
                }
                
                // Fetch ALL episodes from TVMaze for exact airstamps
                mazeEpisodes = (try? await APIClient.shared.fetchTVMazeEpisodes(tvMazeID: mID)) ?? []
            }

            // Update Cast (Always replace to ensure aggregate data and 10-member limit)
            let newCastResults = details.cast
            tvDetails.cast.forEach { modelContext.delete($0) }
            
            var seen = Set<String>()
            var newCastList: [CastMember] = []
            for c in newCastResults {
                if seen.contains(c.name) { continue }
                seen.insert(c.name)
                
                let profileURL = APIClient.tmdbImageURL(path: c.profilePath, size: "w185")
                let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order, mediaID: item.id)
                member.tvShowDetails = tvDetails
                modelContext.insert(member)
                newCastList.append(member)
            }
            tvDetails.cast = newCastList

            if tvDetails.modelContext == nil { modelContext.insert(tvDetails) }
            tvDetails.item = item
            tvDetails.status = await StringPool.shared.intern(details.status)
            tvDetails.originalLanguage = await StringPool.shared.intern(details.originalLanguage)
            tvDetails.network = await StringPool.shared.intern(details.network)
            tvDetails.voteAverage = details.voteAverage
            tvDetails.genres = details.genres
            tvDetails.networkLogoPath = details.networkLogoPath
            tvDetails.numberOfSeasons = details.seasonsCount
            tvDetails.numberOfEpisodes = details.episodesCount
            tvDetails.creators = details.creators.map { $0.name }
            tvDetails.tvMazeID = tvMazeID
            
            if !metadataOnly {
                let shouldFetchAll = force || item.state == .active || item.state == .rewatching || tvDetails.seasons.isEmpty || hasMissingEpisodes || totalCachedEpisodes == 0 || (details.episodesCount < 30)
                let seasonsToSync = shouldFetchAll ? details.seasons : details.seasons.suffix(2)

                for seasonData in seasonsToSync {
                    let sNum = seasonData.season_number
                    
                    // Phase 5: Resiliency Check - Skip empty seasons listed in the brief
                    if seasonData.episode_count == 0 { continue }
                    
                    let seasonUniqueID = "\(tmdbID)_\(sNum)"
                    
                    let sDescriptor = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.uniqueID == seasonUniqueID })
                    let season = (try? modelContext.fetch(sDescriptor).first) ?? TVSeason(seasonNumber: sNum, name: seasonData.name ?? "Season \(sNum)", episodeCount: seasonData.episode_count, airDate: seasonData.air_date, showID: tmdbID)
                    season.showID = tmdbID
                    
                    if season.modelContext == nil || season.tvShowDetails?.persistentModelID != tvDetails.persistentModelID {
                        season.tvShowDetails = tvDetails
                        modelContext.insert(season)
                    }
                    
                    do {
                        let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum)
                        for ep in episodes {
                            let epUniqueID = "\(tmdbID)_\(sNum)_\(ep.episodeNumber)"
                            let eDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.uniqueID == epUniqueID })
                            let epName = ep.name ?? "Episode \(ep.episodeNumber)"
                            let epOverview = ep.overview ?? ""
                            
                            // Try to find matching TVMaze episode for high-precision airstamp
                            let matchingMaze = mazeEpisodes.first { $0.season == sNum && $0.number == ep.episodeNumber }
                            
                            let episode = (try? modelContext.fetch(eDescriptor).first) ?? TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: epName, overview: epOverview, airDate: ep.airDate, airstamp: matchingMaze?.airstamp, runtime: ep.runtime, showID: tmdbID)
                            episode.showID = tmdbID
                            
                            if episode.modelContext == nil || episode.season?.persistentModelID != season.persistentModelID {
                                episode.season = season
                                modelContext.insert(episode)
                            } else {
                                episode.name = epName
                                episode.overview = epOverview
                                episode.airDate = ep.airDate
                                episode.airstamp = matchingMaze?.airstamp
                                episode.runtime = ep.runtime
                                episode.updateAirDateValue()
                            }
                        }
                    } catch {
                        // Phase 5: Resilience - If one season fails, log it but continue with the rest of the show refresh
                        print("⚠️ Failed to sync season \(sNum) for show \(tmdbID): \(error)")
                    }
                }
                tvDetails.recalculateCachedProperties()
            }
            
            item.lastUpdated = Date()
            return true
        } catch {
            return false
        }
    }
}
