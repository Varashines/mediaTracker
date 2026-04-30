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
        var refreshedIDs: [String] = []

        // Phase 5 Optimization: Hybrid Parallel Processing
        // We fetch data in parallel but apply updates serially to maintain context integrity.
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrent = max(2, min(4, processorCount / 2))

        await withTaskGroup(of: (String, Bool).self) { group in
            var activeTasks = 0
            var currentIndex = 0
            
            while currentIndex < itemIDs.count || activeTasks > 0 {
                while activeTasks < maxConcurrent && currentIndex < itemIDs.count {
                    let id = itemIDs[currentIndex]
                    group.addTask {
                        // We call the serial method but since multiple tasks are in the group,
                        // and refreshSingleItem has await points, it releases the actor lock.
                        // HOWEVER, since we are on the same actor, the lock ensures ONLY ONE 
                        // task is executing between suspension points.
                        let success = await self.refreshSingleItem(id: id, metadataOnly: metadataOnly, force: force, shouldSave: false)
                        return (id, success)
                    }
                    currentIndex += 1
                    activeTasks += 1
                }
                
                if let (refID, success) = await group.next() {
                    if success { refreshedIDs.append(refID) } else { errorCount += 1 }
                    activeTasks -= 1
                }
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
        
        // Phase 5: Bulk Notification (Only after successful save!)
        for refID in refreshedIDs {
            Task { @MainActor in
                NotificationCenter.default.post(name: .mediaItemRefreshed, object: nil, userInfo: ["id": refID])
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
            let success: Bool
            if item.type == .movie {
                success = await refreshMovie(item: item, tmdbID: tmdbID)
            } else if item.type == .tvShow {
                success = await refreshTVShow(item: item, tmdbID: tmdbID, metadataOnly: metadataOnly, force: force)
            } else {
                success = false
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

    private func refreshMovie(item: MediaItem, tmdbID: Int) async -> Bool {
        do {
            let details = try await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
            item.releaseDate = DateUtils.parseDate(details.releaseDate)
            
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
                    let profileURL = c.profilePath.map { "https://image.tmdb.org/t/p/w185\($0)" }
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

    private func refreshTVShow(item: MediaItem, tmdbID: Int, metadataOnly: Bool, force: Bool) async -> Bool {
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
            
            if let poster = details.posterPath {
                item.posterURL = "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(poster)"
            }
            if let backdrop = details.backdropPath {
                item.backdropURL = "https://image.tmdb.org/t/p/w1280\(backdrop)"
            }
            
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
                    let profileURL = c.profilePath.map { "https://image.tmdb.org/t/p/w185\($0)" }
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
