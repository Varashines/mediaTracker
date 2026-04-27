import Foundation
import SwiftData

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

    func refreshMetadata(for itemIDs: [String], metadataOnly: Bool = false, force: Bool = false) async {
        if isThermalThrottled {
            print("🌡️ Thermal state serious or Low Power Mode active. Skipping background refresh.")
            return
        }
        
        var errorCount = 0
        
        // Phase 2 Optimization: CPU-Aware Throttling
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrent = max(2, min(5, processorCount / 2))
        
        // Use withTaskGroup to throttle network requests
        var refreshedIDs: [String] = []
        await withTaskGroup(of: (String, Bool).self) { group in
            var activeTasks = 0
            
            for id in itemIDs {
                if activeTasks >= maxConcurrent {
                    if let (refID, success) = await group.next() {
                        if success { refreshedIDs.append(refID) } else { errorCount += 1 }
                    }
                    activeTasks -= 1
                }
                
                group.addTask {
                    let success = await self.refreshSingleItem(id: id, metadataOnly: metadataOnly, force: force, shouldSave: false)
                    return (id, success)
                }
                activeTasks += 1
            }
            
            while activeTasks > 0 {
                if let (refID, success) = await group.next() {
                    if success { refreshedIDs.append(refID) } else { errorCount += 1 }
                }
                activeTasks -= 1
            }
        }

        // Phase 2 Optimization: Batch Save
        try? modelContext.save()
        
        // Phase 5: Bulk Notification (Only after save!)
        for refID in refreshedIDs {
            Task { @MainActor in
                NotificationCenter.default.post(name: .mediaItemRefreshed, object: nil, userInfo: ["id": refID])
            }
        }
        
        print("✅ Background Refresh: Completed with \(errorCount) errors.")
    }

    func refreshSingleItem(id: String, metadataOnly: Bool = false, force: Bool = false, shouldSave: Bool = true) async -> Bool {
        // Crash Prevention: Use a safe fetch descriptor instead of model(for:) with PersistentIdentifier.
        // This avoids crashing if the item was deleted or hasn't been committed yet.
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return false }
        
        let tmdbIDString = item.id.split(separator: "_").last ?? item.id[...]
        guard let tmdbID = Int(tmdbIDString) else { return false }

        do {
            if item.type == .movie {
                let details = try await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                
                // Diff-based update
                item.releaseDate = DateUtils.parseDate(details.releaseDate)
                
                // Poster & Backdrop Upgrade
                if let poster = details.posterPath {
                    item.posterURL = "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(poster)"
                }
                if let backdrop = details.backdropPath {
                    item.backdropURL = "https://image.tmdb.org/t/p/w1280\(backdrop)"
                }
                
                let movieDetails = item.movieDetails ?? MovieDetails(tmdbID: tmdbID)
                movieDetails.item = item
                movieDetails.runtime = details.runtime
                movieDetails.genres = details.genres
                movieDetails.voteAverage = details.voteAverage
                movieDetails.originalLanguage = await StringPool.shared.intern(details.originalLanguage)
                movieDetails.creators = details.directors.map { $0.name }
                
                // Update Cast - Only if changed
                let newCastResults = details.cast
                let currentCast = item.displayCast
                let hasChanged = currentCast.count != newCastResults.count || 
                                zip(currentCast.sorted(by: { $0.name < $1.name }), 
                                    newCastResults.sorted(by: { $0.name < $1.name }))
                                .contains(where: { $0.0.name != $0.1.name || $0.0.characterName != $0.1.character })

                if hasChanged || movieDetails.cast.isEmpty {
                    let oldCast = movieDetails.cast
                    for member in oldCast { modelContext.delete(member) }
                    
                    var newCastList: [CastMember] = []
                    for c in newCastResults {
                        let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                        let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                        member.movieDetails = movieDetails
                        modelContext.insert(member)
                        newCastList.append(member)
                    }
                    movieDetails.cast = newCastList
                }
                
                if movieDetails.modelContext == nil { modelContext.insert(movieDetails) }
                
                item.lastUpdated = Date()
                
            } else if item.type == .tvShow {
                let details = try await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
                
                // Phase 2 Optimization: Head-Only Smart Refresh
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
                    // Just update a few key bits without full season sync
                    tvDetails.nextEpisodeDate = DateUtils.parseEpisodeDate(details.nextEpisodeDate, serviceName: tvDetails.network, for: tvDetails)
                    tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
                    tvDetails.nextSeasonNumber = details.nextSeasonNumber
                    item.lastUpdated = Date()
                    return true
                }

                // Nil-safe date update
                if let newDate = DateUtils.parseDate(details.firstAirDate) {
                    item.releaseDate = newDate
                }
                
                // Poster & Backdrop Upgrade
                if let poster = details.posterPath {
                    item.posterURL = "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(poster)"
                }
                if let backdrop = details.backdropPath {
                    item.backdropURL = "https://image.tmdb.org/t/p/w1280\(backdrop)"
                }
                
                // Parallel Season Fetching
                var tvMazeID: Int? = nil
                
                if let tvdbID = details.tvdbID {
                    // Phase 2 Optimization: Persisted TVMaze ID
                    if let existingMazeID = tvDetails.tvMazeID {
                        tvMazeID = existingMazeID
                    } else if let mID = try? await APIClient.shared.lookupTVMazeID(tvdbID: tvdbID) {
                        tvMazeID = mID
                    }
                    
                    if let mID = tvMazeID {
                        if let (episode, timezone, service) = try? await APIClient.shared.fetchTVMazeSchedule(tvMazeID: mID), let schedule = episode {
                            tvDetails.nextEpisodeDate = DateUtils.parseFullDate(dateString: schedule.airdate, timeString: schedule.airtime, airstamp: schedule.airstamp, timezone: timezone, serviceName: service, item: item)
                        }
                    }
                }

                // Update Cast - Only if changed
                let newCastResults = details.cast
                let currentCast = item.displayCast
                let hasCastChanged = currentCast.count != newCastResults.count || 
                                   zip(currentCast.sorted(by: { $0.name < $1.name }), 
                                       newCastResults.sorted(by: { $0.name < $1.name }))
                                   .contains(where: { $0.0.name != $0.1.name || $0.0.characterName != $0.1.character })

                if hasCastChanged || tvDetails.cast.isEmpty {
                    let oldCast = tvDetails.cast
                    for member in oldCast { modelContext.delete(member) }
                    
                    var newCastList: [CastMember] = []
                    for c in newCastResults {
                        let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                        let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                        member.tvShowDetails = tvDetails
                        modelContext.insert(member)
                        newCastList.append(member)
                    }
                    tvDetails.cast = newCastList
                }

                // Diff-based Sync
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
                    // FORCE FULL SYNC if episodes are missing (totalCount == 0) or any season is empty
                    let shouldFetchAll = force || item.state == .active || item.state == .rewatching || tvDetails.seasons.isEmpty || hasMissingEpisodes || totalCachedEpisodes == 0 || (details.episodesCount < 30)
                    let seasonsToSync = shouldFetchAll ? details.seasons : details.seasons.suffix(2)

                    for seasonData in seasonsToSync {
                        let sNum = seasonData.season_number
                        let season = tvDetails.seasons.first(where: { $0.seasonNumber == sNum }) ?? TVSeason(seasonNumber: sNum, name: seasonData.name, episodeCount: seasonData.episode_count, airDate: seasonData.air_date, showID: tmdbID)
                        
                        if season.modelContext == nil {
                            season.tvShowDetails = tvDetails
                            modelContext.insert(season)
                            // FORCE SYNC: Explicitly append to parent array to trigger MainActor redraw
                            if !tvDetails.seasons.contains(where: { $0.seasonNumber == sNum }) {
                                tvDetails.seasons.append(season)
                            }
                        }
                        
                        if let episodes = try? await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum) {
                            for ep in episodes {
                                let episode = season.episodes.first(where: { $0.episodeNumber == ep.episodeNumber }) ?? TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: ep.name, overview: ep.overview, airDate: ep.airDate, runtime: ep.runtime, showID: tmdbID)
                                
                                if episode.modelContext == nil {
                                    episode.season = season
                                    modelContext.insert(episode)
                                    // FORCE SYNC: Explicitly append to parent array to trigger MainActor redraw
                                    if !season.episodes.contains(where: { $0.episodeNumber == ep.episodeNumber }) {
                                        season.episodes.append(episode)
                                    }
                                } else {
                                    episode.name = ep.name
                                    episode.overview = ep.overview
                                    episode.airDate = ep.airDate
                                    episode.runtime = ep.runtime
                                }
                            }
                        } else {
                            print("⚠️ Failed to fetch episodes for \(item.title) season \(sNum).")
                        }
                    }
                    tvDetails.recalculateCachedProperties()
                }
                
                item.lastUpdated = Date()
            }
            
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
}
