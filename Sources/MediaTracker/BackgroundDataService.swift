import Foundation
import SwiftData

/// Phase 1: Data Integrity - Global coordinator to prevent duplicate sync tasks for the same TMDB ID.
actor SyncCoordinator {
    static let shared = SyncCoordinator()
    private var inFlightSyncs: [Int: Task<Bool, Error>] = [:]

    func performSync(tmdbID: Int, operation: @Sendable @escaping () async throws -> Bool) async throws -> Bool {
        if let existingTask = inFlightSyncs[tmdbID] {
            return try await existingTask.value
        }

        let task = Task {
            try await operation()
        }

        inFlightSyncs[tmdbID] = task
        
        do {
            let result = try await task.value
            inFlightSyncs[tmdbID] = nil
            return result
        } catch {
            inFlightSyncs[tmdbID] = nil
            throw error
        }
    }
}

/// A background actor for heavy SwiftData operations and throttled networking.
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

    func importLibraryData(backup: LibraryBackup) async -> Int {
        let descriptor = FetchDescriptor<MediaItem>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingKeys = Set(existing.map { "\($0.id)_\($0.type?.rawValue ?? "")" })
        
        var importedCount = 0
        for itemData in backup.items {
            let typePrefix = itemData.type.lowercased().contains("movie") ? "movie" : "tv"
            let uniqueID = "\(typePrefix)_\(itemData.id.split(separator: "_").last ?? itemData.id[...])"
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
            }
        }
        
        try? modelContext.save()
        return importedCount
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
            let success = try await SyncCoordinator.shared.performSync(tmdbID: tmdbID) {
                let success: Bool
                if itemType == .movie {
                    success = await self.refreshMovie(id: id, tmdbID: tmdbID)
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
                await NotificationManager.shared.scheduleMovieNotification(
                    id: item.id, 
                    title: item.title, 
                    releaseDate: item.releaseDate, 
                    posterURL: item.posterURL
                )
            } else if item.type == .tvShow, let tv = item.tvShowDetails {
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
        guard let item = try? modelContext.fetch(descriptor).first,
              let tv = item.tvShowDetails else { return }
        
        for season in tv.seasons {
            for episode in season.episodes {
                episode.isWatched = true
            }
        }
        
        item.lastInteractionDate = Date()
        item.syncCachedProperties()
        item.updateSearchableText()
        item.checkOverallCompletion()
        
        do {
            try modelContext.save()
        } catch {
            print("❌ Background: Failed to save markAllAsWatched: \(error)")
        }
    }

    private func refreshMovie(id: String, tmdbID: Int) async -> Bool {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return false }
        
        do {
            let details = try await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
            item.releaseDate = DateUtils.parseDate(details.releaseDate)
            
            item.posterURL = APIClient.tmdbImageURL(path: details.posterPath)
            item.backdropURL = APIClient.tmdbImageURL(path: details.backdropPath, size: "w1280")
            
            let movieDetails = item.movieDetails ?? MovieDetails(tmdbID: tmdbID)
            movieDetails.item = item
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
                
                var newCastList: [CastMember] = []
                for c in newCastResults {
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
            let details = try await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
            let tvDetails = item.tvShowDetails ?? TVShowDetails(tmdbID: tmdbID)
            
            let totalCachedEpisodes = tvDetails.seasons.reduce(0) { $0 + $1.episodes.count }
            let hasMissingEpisodes = tvDetails.seasons.contains(where: { $0.episodes.isEmpty }) && !tvDetails.seasons.isEmpty

            let isAlreadyCurrent = !force && 
                                 tvDetails.numberOfEpisodes == details.episodesCount && 
                                 tvDetails.status == details.status && 
                                 item.releaseDate != nil &&
                                 !metadataOnly &&
                                 !tvDetails.seasons.isEmpty &&
                                 !hasMissingEpisodes &&
                                 totalCachedEpisodes > 0
            
            if isAlreadyCurrent && item.state != .active {
                tvDetails.nextEpisodeDate = DateUtils.parseEpisodeDate(details.nextEpisodeDate, serviceName: tvDetails.network, for: tvDetails)
                tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
                tvDetails.nextSeasonNumber = details.nextSeasonNumber
                item.lastUpdated = Date()
                return true
            }

            if let newDate = DateUtils.parseDate(details.firstAirDate) {
                item.releaseDate = newDate
            }
            
            item.posterURL = APIClient.tmdbImageURL(path: details.posterPath)
            item.backdropURL = APIClient.tmdbImageURL(path: details.backdropPath, size: "w1280")
            
            var tvMazeID = tvDetails.tvMazeID
            if let tvdbID = details.tvdbID, tvMazeID == nil {
                tvMazeID = try? await APIClient.shared.lookupTVMazeID(tvdbID: tvdbID)
            }
            
            if let mID = tvMazeID {
                if let (episode, timezone, service) = try? await APIClient.shared.fetchTVMazeSchedule(tvMazeID: mID), let schedule = episode {
                    tvDetails.nextEpisodeDate = DateUtils.parseFullDate(dateString: schedule.airdate, timeString: schedule.airtime, airstamp: schedule.airstamp, timezone: timezone, serviceName: service, item: item)
                }
            }

            // Update Cast
            let newCastResults = details.cast
            let currentCast = item.displayCast
            let hasCastChanged = currentCast.count != newCastResults.count || 
                               zip(currentCast.sorted(by: { $0.name < $1.name }), 
                                   newCastResults.sorted(by: { $0.name < $1.name }))
                               .contains(where: { $0.0.name != $0.1.name || $0.0.characterName != $0.1.character })

            if hasCastChanged || tvDetails.cast.isEmpty {
                tvDetails.cast.forEach { modelContext.delete($0) }
                
                var newCastList: [CastMember] = []
                for c in newCastResults {
                    let profileURL = APIClient.tmdbImageURL(path: c.profilePath, size: "w185")
                    let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order, mediaID: item.id)
                    member.tvShowDetails = tvDetails
                    modelContext.insert(member)
                    newCastList.append(member)
                }
                tvDetails.cast = newCastList
            }

            if tvDetails.modelContext == nil { modelContext.insert(tvDetails) }
            tvDetails.item = item
            tvDetails.voteAverage = details.voteAverage
            tvDetails.genres = details.genres
            tvDetails.network = await StringPool.shared.intern(details.network)
            tvDetails.networkLogoPath = details.networkLogoPath
            tvDetails.originalLanguage = await StringPool.shared.intern(details.originalLanguage)
            tvDetails.status = await StringPool.shared.intern(details.status)
            tvDetails.creators = details.creators.map { $0.name }
            tvDetails.numberOfSeasons = details.seasonsCount
            tvDetails.numberOfEpisodes = details.episodesCount
            tvDetails.tvMazeID = tvMazeID
            tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
            tvDetails.nextSeasonNumber = details.nextSeasonNumber
            
            if !metadataOnly {
                let shouldFetchAll = force || item.state == .active || item.state == .rewatching || tvDetails.seasons.isEmpty || hasMissingEpisodes || totalCachedEpisodes == 0 || (details.episodesCount < 30)
                let seasonsToSync = shouldFetchAll ? details.seasons : details.seasons.suffix(2)

                for seasonData in seasonsToSync {
                    let sNum = seasonData.season_number
                    let seasonUniqueID = "\(tmdbID)_\(sNum)"
                    
                    let sDescriptor = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.uniqueID == seasonUniqueID })
                    let season = (try? modelContext.fetch(sDescriptor).first) ?? TVSeason(seasonNumber: sNum, name: seasonData.name, episodeCount: seasonData.episode_count, airDate: seasonData.air_date, showID: tmdbID)
                    
                    if season.modelContext == nil {
                        season.tvShowDetails = tvDetails
                        modelContext.insert(season)
                    }
                    
                    if let episodes = try? await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum) {
                        for ep in episodes {
                            let epUniqueID = "\(tmdbID)_\(sNum)_\(ep.episodeNumber)"
                            let eDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.uniqueID == epUniqueID })
                            let episode = (try? modelContext.fetch(eDescriptor).first) ?? TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: ep.name, overview: ep.overview, airDate: ep.airDate, runtime: ep.runtime, showID: tmdbID)
                            
                            if episode.modelContext == nil {
                                episode.season = season
                                modelContext.insert(episode)
                            } else {
                                episode.name = ep.name
                                episode.overview = ep.overview
                                episode.airDate = ep.airDate
                                episode.runtime = ep.runtime
                                episode.updateAirDateValue()
                            }
                        }
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
