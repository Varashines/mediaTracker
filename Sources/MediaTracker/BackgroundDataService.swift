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

    func refreshMetadata(for itemIDs: [PersistentIdentifier], metadataOnly: Bool = false) async {
        if isThermalThrottled {
            print("🌡️ Thermal state serious or Low Power Mode active. Skipping background refresh.")
            return
        }
        
        var errorCount = 0
        
        // Phase 2 Optimization: CPU-Aware Throttling
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrent = max(2, min(5, processorCount / 2))
        
        // Use withTaskGroup to throttle network requests
        await withTaskGroup(of: Bool.self) { group in
            var activeTasks = 0
            
            for id in itemIDs {
                if activeTasks >= maxConcurrent {
                    if await !group.next()! { errorCount += 1 }
                    activeTasks -= 1
                }
                
                group.addTask {
                    await self.refreshSingleItem(id: id, metadataOnly: metadataOnly)
                }
                activeTasks += 1
            }
            
            while activeTasks > 0 {
                if await !group.next()! { errorCount += 1 }
                activeTasks -= 1
            }
        }
        
        print("✅ Background Refresh: Completed with \(errorCount) errors.")
    }

    func refreshSingleItem(id: PersistentIdentifier, metadataOnly: Bool = false) async -> Bool {
        // Crash Prevention: Ensure the item still exists in the store before processing
        guard let item = modelContext.model(for: id) as? MediaItem else { return false }
        
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
                    item.backdropURL = "https://image.tmdb.org/t/p/w780\(backdrop)"
                }
                
                let movieDetails = item.movieDetails ?? MovieDetails(tmdbID: tmdbID)
                movieDetails.item = item
                movieDetails.runtime = details.runtime
                movieDetails.genres = details.genres
                movieDetails.voteAverage = details.voteAverage
                movieDetails.originalLanguage = details.originalLanguage
                movieDetails.creators = details.directors.map { $0.name }
                
                // Sync Cast
                for member in movieDetails.cast { modelContext.delete(member) }
                var newCastList: [CastMember] = []
                for c in details.cast {
                    let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                    let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                    member.movieDetails = movieDetails
                    modelContext.insert(member)
                    newCastList.append(member)
                }
                movieDetails.cast = newCastList
                
                if movieDetails.modelContext == nil { modelContext.insert(movieDetails) }
                
                item.lastUpdated = Date()
                
            } else if item.type == .tvShow {
                let details = try await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
                
                // Phase 2 Optimization: Head-Only Smart Refresh
                let tvDetails = item.tvShowDetails ?? TVShowDetails(tmdbID: tmdbID)
                
                let totalCachedEpisodes = tvDetails.seasons.reduce(0) { $0 + $1.episodes.count }
                let hasMissingEpisodes = tvDetails.seasons.contains(where: { $0.episodes.isEmpty }) && !tvDetails.seasons.isEmpty

                let isAlreadyCurrent = tvDetails.numberOfEpisodes == details.episodesCount && 
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
                    item.backdropURL = "https://image.tmdb.org/t/p/w780\(backdrop)"
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

                // Update Cast
                for member in tvDetails.cast { modelContext.delete(member) }
                var newCastList: [CastMember] = []
                for c in details.cast {
                    let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                    let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                    member.tvShowDetails = tvDetails
                    modelContext.insert(member)
                    newCastList.append(member)
                }

                // Diff-based Sync
                if tvDetails.modelContext == nil { modelContext.insert(tvDetails) }
                tvDetails.item = item
                
                tvDetails.voteAverage = details.voteAverage
                tvDetails.genres = details.genres
                tvDetails.network = details.network
                tvDetails.networkLogoPath = details.networkLogoPath
                tvDetails.originalLanguage = details.originalLanguage
                tvDetails.status = details.status
                tvDetails.numberOfSeasons = details.seasonsCount
                tvDetails.numberOfEpisodes = details.episodesCount
                tvDetails.tvMazeID = tvMazeID
                tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
                tvDetails.nextSeasonNumber = details.nextSeasonNumber
                tvDetails.creators = details.creators.map { $0.name }
                tvDetails.cast = newCastList
                
                if !metadataOnly {
                    // FORCE FULL SYNC if episodes are missing (totalCount == 0) or any season is empty
                    let shouldFetchAll = item.state == .active || item.state == .rewatching || tvDetails.seasons.isEmpty || hasMissingEpisodes || totalCachedEpisodes == 0 || (details.episodesCount < 30)
                    let seasonsToSync = shouldFetchAll ? details.seasons : details.seasons.suffix(2)

                    for seasonData in seasonsToSync {
                        let sNum = seasonData.season_number
                        let season = tvDetails.seasons.first(where: { $0.seasonNumber == sNum }) ?? TVSeason(seasonNumber: sNum, name: seasonData.name, episodeCount: seasonData.episode_count, airDate: seasonData.air_date, showID: tmdbID)
                        
                        if season.modelContext == nil {
                            season.tvShowDetails = tvDetails
                            modelContext.insert(season)
                        }
                        
                        let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum)
                        for ep in episodes {
                            let episode = season.episodes.first(where: { $0.episodeNumber == ep.episodeNumber }) ?? TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: ep.name, overview: ep.overview, airDate: ep.airDate, runtime: ep.runtime, showID: tmdbID)
                            
                            if episode.modelContext == nil {
                                episode.season = season
                                modelContext.insert(episode)
                            } else {
                                episode.name = ep.name
                                episode.overview = ep.overview
                                episode.airDate = ep.airDate
                                episode.runtime = ep.runtime
                            }
                        }
                    }
                    tvDetails.recalculateCachedProperties()
                }
                
                item.lastUpdated = Date()
            }
            
            item.syncCachedProperties()
            item.updateSearchableText()
            try modelContext.save()
            return true
        } catch {
            print("❌ Refresh error for \(item.title): \(error)")
            return false
        }
    }
}
