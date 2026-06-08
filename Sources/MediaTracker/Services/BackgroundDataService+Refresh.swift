import Foundation
import SwiftData
import AppKit

extension BackgroundDataService {
    func refreshMovie(id: String, tmdbID: Int, force: Bool = false) async -> Bool {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return false }
        
        do {
            let details = try await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID, force: force)
            item.releaseDate = DateUtils.parseDate(details.releaseDate)
            if let newOverview = details.overview {
                item.overview = newOverview
            }
            
            item.posterURL = APIClient.tmdbImageURL(path: details.posterPath) ?? item.posterURL
            item.backdropURL = APIClient.tmdbImageURL(path: details.backdropPath, size: "w1280")
            
            let movieDetails = item.movieDetails ?? MovieDetails(tmdbID: tmdbID)
            movieDetails.item = item
            item.movieDetails = movieDetails
            movieDetails.runtime = details.runtime
            movieDetails.genres = details.genres
            movieDetails.voteAverage = details.voteAverage
            movieDetails.originalLanguage = details.originalLanguage
            movieDetails.creators = details.directors.map { $0.name }
            // Skip OMDB for Wishlist items without taste ratings — minimal value
            if !(item.state == .wishlist && item.tasteValue == TasteValue.none.rawValue) {
                if let imdbID = details.imdbID, let omdb = await APIClient.shared.fetchOMDBData(imdbID: imdbID) {
                    movieDetails.rottenTomatoesScore = omdb.rottenTomatoesScore
                    movieDetails.imdbRating = omdb.imdbRating
                    movieDetails.contentRating = omdb.contentRating
                }
            }
            let prodNames = details.productionCompanies.map { $0.name }
            let prodLogos = details.productionCompanies.map { $0.logoPath ?? "" }
            movieDetails.network = prodNames.isEmpty ? nil : prodNames.joined(separator: ",")
            movieDetails.networkLogoPath = prodLogos.isEmpty ? nil : prodLogos.joined(separator: ",")
            
            let newCastResults = details.cast
            let currentCast = item.displayCast
            // Short-circuit: quick check before expensive sort-and-zip
            let hasChanged = currentCast.count != newCastResults.count ||
                            (currentCast.first?.name != newCastResults.first?.name) ||
                            (currentCast.last?.name != newCastResults.last?.name) ||
                            zip(currentCast.sorted(by: { $0.name < $1.name }), 
                                newCastResults.sorted(by: { $0.name < $1.name }))
                            .contains(where: { $0.0.name != $0.1.name || $0.0.characterName != $0.1.character })

            if hasChanged || movieDetails.cast.isEmpty {
                movieDetails.cast.forEach { modelContext.delete($0) }
                
                var seen = Set<String>()
                var newCastList: [CastMember] = []
                for c in newCastResults {
                    let key = "\(c.name)|\(c.character)"
                    if seen.contains(key) { continue }
                    seen.insert(key)
                    
                    let profileURL = APIClient.tmdbImageURL(path: c.profilePath, size: "w185")
                    let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order, mediaID: item.id)
                    member.movieDetails = movieDetails
                    modelContext.insert(member)
                    newCastList.append(member)
                }
                movieDetails.cast = newCastList
            }
            
            if movieDetails.modelContext == nil { modelContext.insert(movieDetails) }
            item.cachedTrailerKey = details.trailerKey
            await extractAndSavePosterColor(for: item)
            item.syncCachedProperties(force: true)
            item.updateSearchableText()
            item.lastUpdated = Date()
            return true
        } catch {
            return false
        }
    }

    func refreshTVShow(id: String, tmdbID: Int, metadataOnly: Bool = false, force: Bool = false) async -> Bool {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? modelContext.fetch(descriptor).first else { return false }

        do {
            let details = try await APIClient.shared.fetchTVDetails(tmdbID: tmdbID, force: force)
            let tvDetails = item.tvShowDetails ?? TVShowDetails(tmdbID: tmdbID)
            tvDetails.item = item
            item.tvShowDetails = tvDetails
            
            if let newDate = DateUtils.parseDate(details.firstAirDate) {
                item.releaseDate = newDate
            }
            if let newOverview = details.overview {
                item.overview = newOverview
            }
            
            item.posterURL = APIClient.tmdbImageURL(path: details.posterPath) ?? item.posterURL
            item.backdropURL = APIClient.tmdbImageURL(path: details.backdropPath, size: "w1280")
            
            tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
            tvDetails.nextSeasonNumber = details.nextSeasonNumber
            if let tmdbNextDate = details.nextEpisodeDate {
                tvDetails.nextEpisodeDate = DateUtils.parseDate(tmdbNextDate)
            }
            
            var tvMazeID = tvDetails.tvMazeID
            if let tvdbID = details.tvdbID, tvMazeID == nil {
                tvMazeID = try? await APIClient.shared.lookupTVMazeID(tvdbID: tvdbID)
            }
            if tvMazeID == nil {
                tvMazeID = try? await APIClient.shared.lookupTVMazeIDByName(title: item.title)
            }
            
            var mazeEpisodes: [TVMazeEpisode] = []
            var mazeGenres: [String]?
            // Skip TVMaze calls for completed/dropped shows with no upcoming episodes
            let hasUpcomingEpisode = details.nextEpisodeDate != nil
            let isActiveShow = item.state == .active || item.state == .rewatching
            
            if let mID = tvMazeID, (isActiveShow || hasUpcomingEpisode) {
                if let (episode, timezone, service, airtime, genres) = try? await APIClient.shared.fetchTVMazeSchedule(tvMazeID: mID) {
                    tvDetails.timezone = timezone
                    tvDetails.nextEpisodeTime = airtime
                    mazeGenres = genres
                    
                    if let schedule = episode {
                        tvDetails.nextEpisodeDate = DateUtils.parseEpisodeDate(schedule.airdate, time: schedule.airtime, airstamp: schedule.airstamp, timezone: timezone, serviceName: service)
                        
                        if let sNum = schedule.season { tvDetails.nextSeasonNumber = sNum }
                        if let eNum = schedule.number { tvDetails.nextEpisodeNumber = eNum }
                    }
                }
                
                // Only fetch full episode list for active shows (airstamp data needed for scheduling)
                if isActiveShow {
                    mazeEpisodes = (try? await APIClient.shared.fetchTVMazeEpisodes(tvMazeID: mID)) ?? []
                }
            }

            let mazeDict: [String: TVMazeEpisode] = {
                var dict: [String: TVMazeEpisode] = [:]
                dict.reserveCapacity(mazeEpisodes.count)
                for ep in mazeEpisodes {
                    if let s = ep.season, let n = ep.number {
                        dict["\(s)_\(n)"] = ep
                    }
                }
                return dict
            }()

            let newCastResults = details.cast
            let currentCast = tvDetails.cast
            // Short-circuit: quick check before expensive sort-and-zip
            let hasChanged = currentCast.count != newCastResults.count ||
                            (currentCast.first?.name != newCastResults.first?.name) ||
                            (currentCast.last?.name != newCastResults.last?.name) ||
                            zip(currentCast.sorted(by: { $0.name < $1.name }),
                                newCastResults.sorted(by: { $0.name < $1.name }))
                            .contains(where: { $0.0.name != $0.1.name || $0.0.characterName != $0.1.character })

            if hasChanged || tvDetails.cast.isEmpty {
                tvDetails.cast.forEach { modelContext.delete($0) }
            
            var seen = Set<String>()
            var newCastList: [CastMember] = []
            for c in newCastResults {
                let key = "\(c.name)|\(c.character)"
                if seen.contains(key) { continue }
                seen.insert(key)
                
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
            tvDetails.status = details.status
            tvDetails.originalLanguage = details.originalLanguage
            tvDetails.voteAverage = details.voteAverage
            // Skip OMDB for Wishlist items without taste ratings — minimal value
            if !(item.state == .wishlist && item.tasteValue == TasteValue.none.rawValue) {
                if let imdbID = details.imdbID, let omdb = await APIClient.shared.fetchOMDBData(imdbID: imdbID) {
                    tvDetails.imdbRating = omdb.imdbRating
                    tvDetails.contentRating = omdb.contentRating
                    tvDetails.rottenTomatoesScore = omdb.rottenTomatoesScore
                }
            }
            // Merge TVMaze genres with TMDB genres (union, standardized)
            let tmdbGenres = details.genres
            if let mazeGenres, !mazeGenres.isEmpty {
                let merged = GenreMapper.standardize(tmdbGenres + mazeGenres)
                tvDetails.genres = merged
            } else {
                tvDetails.genres = tmdbGenres
            }
            // Use TMDB network name and logo (consistent single source)
            tvDetails.network = details.network
            tvDetails.networkLogoPath = details.networkLogoPath
            tvDetails.numberOfSeasons = details.seasonsCount
            tvDetails.numberOfEpisodes = details.episodesCount
            tvDetails.creators = details.creators.map { $0.name }
            tvDetails.tvMazeID = tvMazeID
            item.cachedTrailerKey = details.trailerKey
            
            if !metadataOnly {
                let seasonsToSync = details.seasons

                struct FetchedSeasonData {
                    let seasonNumber: Int
                    let name: String?
                    let episodeCount: Int
                    let airDate: String?
                    let episodes: [TVEpisodeResult]
                }

                let fetchedSeasons: [FetchedSeasonData] = await withTaskGroup(of: FetchedSeasonData?.self) { group in
                    for seasonData in seasonsToSync {
                        let sNum = seasonData.season_number
                        if seasonData.episode_count == 0 { continue }

                        // Skip seasons that already have episodes loaded unless force
                        if !force {
                            let seasonUniqueID = "\(tmdbID)_\(sNum)"
                            let sDescriptor = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.uniqueID == seasonUniqueID })
                            if let existing = try? modelContext.fetch(sDescriptor).first,
                               existing.totalEpisodesCount > 0 {
                                continue
                            }
                        }

                        group.addTask {
                            do {
                                let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum, force: force)
                                return FetchedSeasonData(seasonNumber: sNum, name: seasonData.name, episodeCount: seasonData.episode_count, airDate: seasonData.air_date, episodes: episodes)
                            } catch {
                                AppLogger.warning("⚠️ Failed to fetch season \(sNum) for show \(tmdbID): \(error)", logger: AppLogger.background)
                                return nil
                            }
                        }
                    }
                    var results: [FetchedSeasonData] = []
                    for await result in group {
                        if let result { results.append(result) }
                    }
                    return results.sorted { $0.seasonNumber < $1.seasonNumber }
                }

                for seasonData in fetchedSeasons {
                    let sNum = seasonData.seasonNumber
                    let seasonUniqueID = "\(tmdbID)_\(sNum)"

                    let sDescriptor = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.uniqueID == seasonUniqueID })
                    let season = (try? modelContext.fetch(sDescriptor).first) ?? TVSeason(seasonNumber: sNum, name: seasonData.name ?? "Season \(sNum)", episodeCount: seasonData.episodeCount, airDate: seasonData.airDate, showID: tmdbID)
                    season.showID = tmdbID

                    if season.modelContext == nil {
                        modelContext.insert(season)
                    }
                    if season.tvShowDetails?.persistentModelID != tvDetails.persistentModelID {
                        season.tvShowDetails = tvDetails
                    }

                    for ep in seasonData.episodes {
                        let epUniqueID = "\(tmdbID)_\(sNum)_\(ep.episodeNumber)"
                        let eDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.uniqueID == epUniqueID })
                        let epName = ep.name ?? "Episode \(ep.episodeNumber)"
                        let epOverview = ep.overview ?? ""

                        let matchingMaze = mazeDict["\(sNum)_\(ep.episodeNumber)"]

                        let episode = (try? modelContext.fetch(eDescriptor).first) ?? TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: epName, overview: epOverview, airDate: ep.airDate, airstamp: matchingMaze?.airstamp, runtime: ep.runtime, showID: tmdbID)
                        episode.showID = tmdbID

                        if episode.modelContext == nil {
                            episode.season = season
                            modelContext.insert(episode)
                            episode.updateAirDateValue()
                        } else {
                            if episode.season?.persistentModelID != season.persistentModelID {
                                episode.season = season
                            }
                            episode.name = epName
                            episode.overview = epOverview
                            episode.airDate = ep.airDate
                            episode.airstamp = matchingMaze?.airstamp
                            episode.runtime = ep.runtime
                            episode.updateAirDateValue()
                        }
                    }
                }
                tvDetails.recalculateCachedProperties(triggerSync: true, force: true)
            }
            await extractAndSavePosterColor(for: item)
            item.syncCachedProperties(force: true)
            item.lastUpdated = Date()
            return true
        } catch {
            return false
        }
    }


    func extractAndSavePosterColor(for item: MediaItem) async {
        let shouldExtract = item.themeColorHex == nil || item.themeColorSourceURL != item.posterURL
        guard shouldExtract,
              let poster = item.posterURL else { return }

        // Try to get the image from cache first, avoiding a redundant network download
        var cgImage: CGImage?
        if let cached = await ImageCache.shared.get(forKey: poster, targetSize: CGSize(width: 200, height: 300)) {
            cgImage = cached.image
        } else if let url = URL(string: poster),
                   let (data, _) = try? await ImageCache.shared.imageSession.data(from: url),
                  let image = NSImage(data: data) {
            cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        if let cgImage {
            let pair = await ColorExtractor.topTwoColors(from: cgImage)
            let primaryHex = pair.primary.toHex()
            let secondaryHex = pair.secondary.toHex()
            item.themeColorHex = "\(primaryHex)|\(secondaryHex)"
            item.themeColorSourceURL = poster
        }
    }
}
