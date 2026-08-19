import Foundation
import SwiftData
import AppKit

/// Reconciles one season's TMDB and TVMaze episode data.
/// The union preserves announced episodes that a provider has not listed yet.
/// TVMaze improves generic titles and current air metadata; TMDB remains the
/// runtime authority whenever it has a per-episode value.
enum RuntimeFallback {
    static func reconcile(
        tmdbEpisodes: [TVEpisodeResult],
        tvmazeSeason: [TVMazeEpisode]
    ) -> [TVEpisodeResult] {
        guard !tvmazeSeason.isEmpty else { return tmdbEpisodes }

        let validMazeEpisodes = tvmazeSeason
            .filter { ($0.season ?? 0) > 0 && ($0.number ?? 0) > 0 }
            .sorted { ($0.number ?? 0) < ($1.number ?? 0) }
        guard !validMazeEpisodes.isEmpty else { return tmdbEpisodes }

        let mazeByNumber = Dictionary(
            validMazeEpisodes.map { ($0.number!, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let tmdbNumbers = Set(tmdbEpisodes.map(\.episodeNumber))

        var reconciled = tmdbEpisodes.map { episode in
            guard let mazeEpisode = mazeByNumber[episode.episodeNumber] else {
                return episode
            }

            let mazeName = mazeEpisode.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let shouldUseMazeName = isPlaceholderTitle(episode.name, episodeNumber: episode.episodeNumber)
                && !isPlaceholderTitle(mazeName, episodeNumber: episode.episodeNumber)

            return TVEpisodeResult(
                episodeNumber: episode.episodeNumber,
                name: shouldUseMazeName ? mazeName : episode.name,
                overview: nonEmpty(episode.overview) ?? nonEmpty(mazeEpisode.summary)?
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                airDate: nonEmpty(mazeEpisode.airdate) ?? episode.airDate,
                runtime: episode.runtime ?? mazeEpisode.runtime
            )
        }

        let extras = validMazeEpisodes
            .filter { !tmdbNumbers.contains($0.number!) }
            .map {
                TVEpisodeResult(
                    episodeNumber: $0.number!,
                    name: $0.name,
                    overview: $0.summary?
                        .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    airDate: $0.airdate,
                    runtime: $0.runtime
                )
            }
        reconciled.append(contentsOf: extras)
        return reconciled.sorted { $0.episodeNumber < $1.episodeNumber }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func isPlaceholderTitle(_ title: String?, episodeNumber: Int) -> Bool {
        guard let normalized = nonEmpty(title)?.lowercased() else { return true }
        return normalized == "episode \(episodeNumber)"
            || normalized == "ep \(episodeNumber)"
    }

    static func runtimeMap(
        tmdbEpisodes: [TVEpisodeResult],
        tvmazeSeason: [TVMazeEpisode]
    ) -> [Int: Int] {
        Dictionary(
            reconcile(tmdbEpisodes: tmdbEpisodes, tvmazeSeason: tvmazeSeason)
                .compactMap { episode in
                    episode.runtime.map { (episode.episodeNumber, $0) }
                },
            uniquingKeysWith: { first, _ in first }
        )
    }

    static func validExtras(
        tmdbEpisodeNumbers: Set<Int>,
        tvmazeSeason: [TVMazeEpisode]
    ) -> [TVMazeEpisode] {
        tvmazeSeason.filter {
            guard ($0.season ?? 0) > 0, let number = $0.number, number > 0 else { return false }
            return !tmdbEpisodeNumbers.contains(number)
        }
    }
}

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
            // Short-circuit: quick check before expensive sort-and-zip.
            // Normalize the TMDB list the same way syncCastCache builds storedCast
            // (exclude Creator/Director, dedupe by name+character, cap at 30) so the
            // comparison is like-for-like instead of uncapped-vs-capped.
            var seen = Set<String>()
            var normalizedNew: [CastMemberResult] = []
            for c in newCastResults {
                guard c.character != "Creator", c.character != "Director" else { continue }
                let key = "\(c.name)|\(c.character)"
                guard seen.insert(key).inserted else { continue }
                normalizedNew.append(c)
                if normalizedNew.count >= 30 { break }
            }
            let currentNormalized = currentCast.map { (name: $0.name, character: $0.characterName) }
            let newNormalized = normalizedNew.map { (name: $0.name, character: $0.character) }
            let hasChanged = currentNormalized.count != newNormalized.count ||
                            zip(currentNormalized, newNormalized)
                            .contains(where: { $0.name != $1.name || $0.character != $1.character })

            if hasChanged || movieDetails.cast.isEmpty {
                movieDetails.cast.forEach { modelContext.delete($0) }

                var newCastList: [CastMember] = []
                for c in normalizedNew {
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
            // Look up the TVMaze id if unknown, or re-attempt on a forced refresh
            // (a prior failed lookup stores -1, which would otherwise disable
            // TVMaze episodes/counts for the life of the item).
            let needsLookup = tvMazeID == nil || (force && (tvMazeID ?? -1) <= 0)
            if needsLookup {
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
                
                mazeEpisodes = (try? await APIClient.shared.fetchTVMazeEpisodes(tvMazeID: mID, force: force)) ?? []
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

            // Pre-compute TVMaze episodes grouped by season (Sendable, so it can
            // be captured safely by the concurrent task group).
            let mazeEpisodesBySeason: [Int: [TVEpisodeResult]] = {
                var bySeason: [Int: [TVEpisodeResult]] = [:]
                for ep in mazeEpisodes {
                    guard let s = ep.season, let n = ep.number else { continue }
                    bySeason[s, default: []].append(
                        TVEpisodeResult(
                            episodeNumber: n,
                            name: ep.name,
                            overview: ep.summary?.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines),
                            airDate: ep.airdate,
                            runtime: ep.runtime
                        )
                    )
                }
                for (s, eps) in bySeason {
                    bySeason[s] = eps.sorted { $0.episodeNumber < $1.episodeNumber }
                }
                return bySeason
            }()

            // Raw TVMaze episodes grouped by season for season-level reconciliation.
            let mazeRawBySeason: [Int: [TVMazeEpisode]] = {
                var d: [Int: [TVMazeEpisode]] = [:]
                for ep in mazeEpisodes { if let s = ep.season, s > 0 { d[s, default: []].append(ep) } }
                for (k, v) in d { d[k] = v.sorted { ($0.number ?? 0) < ($1.number ?? 0) } }
                return d
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
            tvDetails.numberOfSeasons = details.numberOfSeasons
            tvDetails.numberOfEpisodes = details.numberOfEpisodes
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
                    /// TMDB per-episode runtimes keyed by episode number. TVMaze is
                    /// the episode-list authority, but runtime comes only from TMDB
                    /// (nil when TMDB has no runtime for an episode).
                    let tmdbRuntimes: [Int: Int]
                    let seasonCast: [SeasonAggregateCastResult]
                    /// True when both episode sources were fetched successfully, so
                    /// an unwatched row absent from their reconciled union is stale.
                    let shouldPruneStaleEpisodes: Bool
                }

                var fetchedSeasons: [FetchedSeasonData] = []

                var didWriteSeasonCast = false

                fetchedSeasons = await withTaskGroup(of: FetchedSeasonData?.self) { group in
                    for seasonData in seasonsToSync {
                        let sNum = seasonData.season_number

                        group.addTask {
                            // Always fetch per-season aggregate credits (new data; existing seasons lack it).
                            let credits = (try? await APIClient.shared.fetchSeasonAggregateCredits(tmdbID: tmdbID, seasonNumber: sNum, force: force)) ?? []

                            // Preserve announced TMDB episodes while enriching matching,
                            // already-published rows with TVMaze data. TVMaze can lag
                            // behind the announced season total for currently airing shows.
                            let usesTVMaze = !(mazeEpisodesBySeason[sNum]?.isEmpty ?? true)
                            let episodes: [TVEpisodeResult]
                            let tmdbEpisodes: [TVEpisodeResult]
                            let fetchedTMDBEpisodes: Bool
                            if let mazeSeasonEps = mazeEpisodesBySeason[sNum], !mazeSeasonEps.isEmpty {
                                do {
                                    tmdbEpisodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum, force: force)
                                    fetchedTMDBEpisodes = true
                                } catch {
                                    AppLogger.warning("⚠️ Failed to fetch TMDB season \(sNum) for show \(tmdbID); preserving existing rows.", logger: AppLogger.background)
                                    tmdbEpisodes = []
                                    fetchedTMDBEpisodes = false
                                }
                                episodes = RuntimeFallback.reconcile(
                                    tmdbEpisodes: tmdbEpisodes,
                                    tvmazeSeason: mazeRawBySeason[sNum] ?? []
                                )
                            } else {
                                do {
                                    tmdbEpisodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum, force: force)
                                    fetchedTMDBEpisodes = true
                                    episodes = tmdbEpisodes
                                } catch {
                                    AppLogger.warning("⚠️ Failed to fetch season \(sNum) for show \(tmdbID): \(error)", logger: AppLogger.background)
                                    return nil
                                }
                            }

                            // TMDB leads; TVMaze fills missing runtimes for matching
                            // episode numbers without allowing a series-wide mismatch to
                            // overwrite otherwise valid season data.
                            let tvmazeRawForSeason = mazeRawBySeason[sNum] ?? []
                            let tmdbRuntimes = RuntimeFallback.runtimeMap(
                                tmdbEpisodes: tmdbEpisodes,
                                tvmazeSeason: tvmazeRawForSeason
                            )
                            return FetchedSeasonData(
                                seasonNumber: sNum,
                                name: seasonData.name,
                                episodeCount: episodes.count,
                                airDate: seasonData.air_date,
                                episodes: episodes,
                                tmdbRuntimes: tmdbRuntimes,
                                seasonCast: credits,
                                shouldPruneStaleEpisodes: usesTVMaze && fetchedTMDBEpisodes
                            )
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
                        let runtime = seasonData.tmdbRuntimes[ep.episodeNumber]

                        let episode = episodeByID[epUniqueID] ?? TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: epName, overview: epOverview, airDate: ep.airDate, airstamp: matchingMaze?.airstamp, runtime: runtime, showID: tmdbID)
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
                            episode.runtime = runtime
                            episode.updateAirDateValue()
                        }
                    }

                    // Delete only episodes absent from both successfully fetched
                    // sources. This avoids removing TMDB-announced future episodes
                    // merely because TVMaze has not published them yet.
                    if seasonData.shouldPruneStaleEpisodes {
                        let validIDs = Set(seasonData.episodes.map { "\(tmdbID)_\(sNum)_\($0.episodeNumber)" })
                        let prefix = "\(tmdbID)_\(sNum)_"
                        for (uid, ep) in episodeByID where uid.hasPrefix(prefix) && !validIDs.contains(uid) {
                            if ep.modelContext != nil { modelContext.delete(ep) }
                        }
                    }

                    // Persist per-season aggregate credits
                    var existingCastByID: [String: SeasonCastMember] = [:]
                    for c in season.seasonCast.liveModels {
                        if let uid = c.uniqueID { existingCastByID[uid] = c }
                    }
                    var seenCastIDs = Set<String>()
                    for cr in seasonData.seasonCast {
                        let uid = "\(tmdbID)_\(sNum)_\(cr.tmdbPersonID)"
                        seenCastIDs.insert(uid)
                        let member = existingCastByID[uid]
                            ?? SeasonCastMember(seasonNumber: sNum, tmdbPersonID: cr.tmdbPersonID, name: cr.name, characterName: cr.characterName, profileURL: cr.profileURL, episodeCount: cr.episodeCount, order: cr.order, showID: tmdbID)
                        member.name = cr.name
                        member.characterName = cr.characterName
                        member.profileURL = cr.profileURL
                        member.episodeCount = cr.episodeCount
                        member.order = cr.order
                        member.seasonNumber = sNum
                        if member.modelContext == nil {
                            member.season = season
                            modelContext.insert(member)
                            didWriteSeasonCast = true
                        } else if member.season?.persistentModelID != season.persistentModelID {
                            member.season = season
                        }
                    }
                    for (uid, member) in existingCastByID where !seenCastIDs.contains(uid) {
                        modelContext.delete(member)
                        didWriteSeasonCast = true
                    }
                }
                tvDetails.recalculateCachedProperties(triggerSync: true, force: true)
                if didWriteSeasonCast {
                    await MainActor.run { TasteActor.clearCache() }
                    ScopedStatsActor.invalidateCache()
                }
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


    /// On-demand fetch of a single season's aggregate credits, persisting
    /// SeasonCastMember rows and invalidating taste caches. Used when a user
    /// requests "This season" cast for a show that hasn't been synced yet.
    func refreshSeasonCast(tmdbID: Int, seasonNumber: Int) async {
        guard let cast = try? await APIClient.shared.fetchSeasonAggregateCredits(tmdbID: tmdbID, seasonNumber: seasonNumber) else { return }

        let seasonUniqueID = "\(tmdbID)_\(seasonNumber)"
        guard let season = (try? modelContext.fetch(FetchDescriptor<TVSeason>(predicate: #Predicate { $0.uniqueID == seasonUniqueID })))?.first else { return }

        var existing: [String: SeasonCastMember] = [:]
        for c in season.seasonCast.liveModels {
            if let uid = c.uniqueID { existing[uid] = c }
        }
        var seen = Set<String>()
        for cr in cast {
            let uid = "\(tmdbID)_\(seasonNumber)_\(cr.tmdbPersonID)"
            seen.insert(uid)
            let member = existing[uid]
                ?? SeasonCastMember(seasonNumber: seasonNumber, tmdbPersonID: cr.tmdbPersonID, name: cr.name, characterName: cr.characterName, profileURL: cr.profileURL, episodeCount: cr.episodeCount, order: cr.order, showID: tmdbID)
            member.name = cr.name
            member.characterName = cr.characterName
            member.profileURL = cr.profileURL
            member.episodeCount = cr.episodeCount
            member.order = cr.order
            if member.modelContext == nil {
                member.season = season
                modelContext.insert(member)
            }
        }
        for (uid, member) in existing where !seen.contains(uid) {
            modelContext.delete(member)
        }

        try? modelContext.save()
        await MainActor.run { TasteActor.clearCache() }
        ScopedStatsActor.invalidateCache()
    }


    func extractAndSavePosterColor(for item: MediaItem) async {        let effectivePoster = item.effectivePosterURL
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
            let palette = await ColorExtractor.extractThemePalette(from: cgImage)
            item.themeColorHex = palette.primary.toHex()
            item.themeSecondaryColorHex = palette.secondary.toHex()
            item.themeMutedColorHex = palette.muted.toHex()
            item.themeColorSourceURL = poster
        }
    }
}
