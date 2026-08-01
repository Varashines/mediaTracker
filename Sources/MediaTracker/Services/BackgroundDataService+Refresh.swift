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
            for director in details.directors {
                if let path = director.profilePath, !path.isEmpty {
                    let check = FetchDescriptor<PersonImageEntity>(predicate: #Predicate { $0.name == director.name })
                    if (try? modelContext.fetch(check).first) == nil {
                        modelContext.insert(PersonImageEntity(name: director.name, profileURL: APIClient.tmdbImageURL(path: path, size: "w185")))
                    }
                }
            }
            // Parallelize OMDB + logos + color extraction
            let itemState = item.state
            let itemTaste = item.tasteValue
            let itemLogoURL = item.titleLogoURL
            async let omdbTask: OMDBFullData? = {
                if !(itemState == .wishlist && itemTaste == TasteValue.none.rawValue),
                   let imdbID = details.imdbID {
                    return await APIClient.shared.fetchOMDBData(imdbID: imdbID)
                }
                return nil
            }()
            
            async let logoTask: String? = {
                if itemLogoURL == nil {
                    return try? await APIClient.shared.fetchMovieLogos(tmdbID: tmdbID, originalLanguage: details.originalLanguage, force: force).first
                }
                return nil
            }()
            
            if let omdb = await omdbTask {
                movieDetails.rottenTomatoesScore = omdb.rottenTomatoesScore
                movieDetails.imdbRating = omdb.imdbRating
                movieDetails.contentRating = omdb.contentRating
            }
            
            if let logo = await logoTask {
                item.titleLogoURL = logo
            }
            
            let prodNames = details.productionCompanies.map { $0.name }
            let prodLogos = details.productionCompanies.map { $0.logoPath ?? "" }
            movieDetails.network = prodNames.isEmpty ? nil : prodNames.joined(separator: ",")
            movieDetails.networkLogoPath = prodLogos.isEmpty ? nil : prodLogos.joined(separator: ",")
            movieDetails.status = details.status
            
            
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
            item.cachedWatchProviders = details.streamingProviders.map { $0.name }
            item.cachedWatchProviderLogoPaths = details.streamingProviders.map { $0.logoPath ?? "" }
            item.syncCachedProperties(dirty: .all)
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
            if tvMazeID == nil {
                if let tvdbID = details.tvdbID {
                    tvMazeID = try? await APIClient.shared.lookupTVMazeID(tvdbID: tvdbID)
                }
                if tvMazeID == nil {
                    tvMazeID = try? await APIClient.shared.lookupTVMazeIDByName(title: item.title)
                }
                tvDetails.tvMazeID = tvMazeID ?? -1
            }
            
            var mazeEpisodes: [TVMazeEpisode] = []
            var mazeGenres: [String]?
            if let mID = tvMazeID, mID > 0 {
                if let (episode, timezone, service, airtime, genres, showType) = try? await APIClient.shared.fetchTVMazeSchedule(tvMazeID: mID) {
                    tvDetails.timezone = timezone
                    tvDetails.nextEpisodeTime = airtime
                    mazeGenres = genres
                    tvDetails.showType = showType
                    
                    if let schedule = episode {
                        tvDetails.nextEpisodeDate = DateUtils.parseEpisodeDate(schedule.airdate, time: schedule.airtime, airstamp: schedule.airstamp, timezone: timezone, serviceName: service)
                        
                        if let sNum = schedule.season { tvDetails.nextSeasonNumber = sNum }
                        if let eNum = schedule.number { tvDetails.nextEpisodeNumber = eNum }
                    }
                }
                
                mazeEpisodes = (try? await APIClient.shared.fetchTVMazeEpisodes(tvMazeID: mID)) ?? []
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
            tvDetails.network = details.network
            tvDetails.networkLogoPath = details.networkLogoPath

            // Merge TMDB + TVMaze genres for richer coverage
            var mergedGenres = Set(details.genres)
            if let mazeGenres {
                for genre in mazeGenres { mergedGenres.insert(genre) }
            }
            tvDetails.genres = Array(mergedGenres)

            tvDetails.creators = details.creators.map { $0.name }
            for creator in details.creators {
                if let path = creator.profilePath, !path.isEmpty {
                    let check = FetchDescriptor<PersonImageEntity>(predicate: #Predicate { $0.name == creator.name })
                    if (try? modelContext.fetch(check).first) == nil {
                        modelContext.insert(PersonImageEntity(name: creator.name, profileURL: APIClient.tmdbImageURL(path: path, size: "w185")))
                    }
                }
            }

            // OMDB fetch (sequential — Sendable issues prevent parallelization with item)
            if !(item.state == .wishlist && item.tasteValue == TasteValue.none.rawValue),
               let imdbID = details.imdbID, !imdbID.isEmpty {
                if let omdb = await APIClient.shared.fetchOMDBData(imdbID: imdbID) {
                    tvDetails.imdbRating = omdb.imdbRating
                    tvDetails.contentRating = omdb.contentRating
                    tvDetails.rottenTomatoesScore = omdb.rottenTomatoesScore
                }
            }
            
            // Logo fetch
            if item.titleLogoURL == nil {
                item.titleLogoURL = try? await APIClient.shared.fetchTVLogos(tmdbID: tmdbID, originalLanguage: details.originalLanguage, force: force).first
            }

            if !metadataOnly {
                let seasonsToSync = details.seasons

                struct FetchedSeasonData {
                    let seasonNumber: Int
                    let name: String?
                    let episodeCount: Int
                    let airDate: String?
                    let episodes: [TVEpisodeResult]
                }

                var fetchedSeasons: [FetchedSeasonData] = []

                fetchedSeasons = await withTaskGroup(of: FetchedSeasonData?.self) { group in
                    for seasonData in seasonsToSync {
                        let sNum = seasonData.season_number
                        if seasonData.episode_count == 0 { continue }

                        var shouldForceSeason = force
                        if !force {
                            let seasonUniqueID = "\(tmdbID)_\(sNum)"
                            let sDescriptor = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.uniqueID == seasonUniqueID })
                            if let existing = try? modelContext.fetch(sDescriptor).first {
                                if existing.episodes.count >= seasonData.episode_count {
                                    continue
                                } else {
                                    shouldForceSeason = true
                                }
                            }
                        }

                        group.addTask {
                            do {
                                let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum, force: shouldForceSeason)
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

                // Batch pre-fetch all existing seasons and episodes for this show to avoid N+1 queries
                let existingSeasonsDesc = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID == tmdbID })
                let existingSeasons = (try? modelContext.fetch(existingSeasonsDesc)) ?? []
                var seasonByID: [String: TVSeason] = [:]
                for s in existingSeasons { if let uid = s.uniqueID { seasonByID[uid] = s } }

                let existingEpisodesDesc = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.showID == tmdbID })
                let existingEpisodes = (try? modelContext.fetch(existingEpisodesDesc)) ?? []
                var episodeByID: [String: TVEpisode] = [:]
                for e in existingEpisodes { if let uid = e.uniqueID { episodeByID[uid] = e } }

                for seasonData in fetchedSeasons {
                    let sNum = seasonData.seasonNumber
                    let seasonUniqueID = "\(tmdbID)_\(sNum)"

                    let season = seasonByID[seasonUniqueID] ?? TVSeason(seasonNumber: sNum, name: seasonData.name ?? "Season \(sNum)", episodeCount: seasonData.episodeCount, airDate: seasonData.airDate, showID: tmdbID)
                    season.showID = tmdbID
                    season.episodeCount = seasonData.episodeCount

                    if season.modelContext == nil {
                        modelContext.insert(season)
                    }
                    if season.tvShowDetails?.persistentModelID != tvDetails.persistentModelID {
                        season.tvShowDetails = tvDetails
                    }

                    for ep in seasonData.episodes {
                        let epUniqueID = "\(tmdbID)_\(sNum)_\(ep.episodeNumber)"
                        let epName = ep.name ?? "Episode \(ep.episodeNumber)"
                        let epOverview = ep.overview ?? ""

                        let matchingMaze = mazeDict["\(sNum)_\(ep.episodeNumber)"]

                        let episode = episodeByID[epUniqueID] ?? TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: epName, overview: epOverview, airDate: ep.airDate, airstamp: matchingMaze?.airstamp, runtime: ep.runtime, showID: tmdbID)
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
            item.cachedWatchProviders = details.streamingProviders.map { $0.name }
            item.cachedWatchProviderLogoPaths = details.streamingProviders.map { $0.logoPath ?? "" }
            if let trailer = details.trailerKey {
                item.cachedTrailerKey = trailer
            }
            await extractAndSavePosterColor(for: item)
            item.syncCachedProperties(dirty: .all)
            item.lastUpdated = Date()
            return true
        } catch {
            return false
        }
    }


    func extractAndSavePosterColor(for item: MediaItem) async {
        let effectivePoster = item.effectivePosterURL
        let shouldExtract = item.themeColorHex == nil || item.themeColorSourceURL != effectivePoster
        guard shouldExtract,
              let poster = effectivePoster else { return }

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
            item.themeColorHex = pair.primary.toHex()
            item.themeColorSourceURL = poster
        }
    }
}
