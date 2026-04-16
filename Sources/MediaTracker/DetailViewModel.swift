import SwiftUI
import SwiftData

@Observable @MainActor
class DetailViewModel {
    var item: MediaItem
    var isRefreshing = false
    var themeColor: Color = Color.secondary.opacity(0.1)
    
    init(item: MediaItem) {
        self.item = item
    }
    
    var needsUpdate: Bool {
        guard let lastUpdated = item.lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 86400
    }
    
    var nextText: String? {
        guard let label = item.nextAiringLabel else { return nil }
        
        let isPast = (item.nextAiringDate ?? Date()) < Date()
        if isPast {
            if item.type == .movie { return "Available Now" }
            let detail = nextEpisodeLabel(for: item.nextAiringDate ?? Date(), hideDate: true)
            return detail.isEmpty ? label : "\(label): \(detail)"
        }
        
        if item.type == .movie { return label }
        return "Next: \(nextEpisodeLabel(for: item.nextAiringDate ?? Date(), hideDate: false))"
    }
    
    func updateThemeColor() {
        if let hex = item.themeColorHex, let cachedColor = Color(hex: hex) {
            self.themeColor = cachedColor
            return
        }

        guard let urlString = item.posterURL, let url = URL(string: urlString) else { return }
        
        Task {
            if let cachedImage = await ImageCache.shared.get(forKey: url.absoluteString) {
                let color = ColorExtractor.dominantColor(from: cachedImage)
                await MainActor.run {
                    withAnimation {
                        self.themeColor = color
                        self.item.themeColorHex = color.toHex()
                    }
                }
            }
        }
    }
    
    func refreshData(force: Bool = false) {
        let hasData = item.movieDetails != nil || (item.type == .tvShow && (item.tvShowDetails != nil && item.tvShowDetails?.status != nil))
        if !force && hasData && !needsUpdate { return }
        
        isRefreshing = true
        let itemType = item.type
        let itemID = item.id
        
        Task {
            do {
                if itemType == .movie, let tmdbID = Int(itemID) {
                    try await refreshMovie(tmdbID: tmdbID)
                } else if itemType == .tvShow, let tmdbID = Int(itemID) {
                    try await refreshTVShow(tmdbID: tmdbID)
                }
                await MainActor.run {
                    updateThemeColor()
                    isRefreshing = false
                }
            } catch {
                print("❌ Refresh error: \(error)")
                await MainActor.run { isRefreshing = false }
            }
        }
    }
    
    private func refreshMovie(tmdbID: Int) async throws {
        let details = try await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
        await MainActor.run {
            item.releaseDate = DateUtils.parseDate(details.releaseDate)
            let movieDetails = item.movieDetails ?? MovieDetails(tmdbID: tmdbID)
            movieDetails.runtime = details.runtime
            movieDetails.genres = details.genres
            movieDetails.voteAverage = details.voteAverage
            
            // Update Cast
            movieDetails.cast.removeAll()
            for c in details.cast {
                let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                movieDetails.cast.append(CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order))
            }
            
            item.movieDetails = movieDetails
            item.lastUpdated = Date()
            SpotlightManager.shared.indexItem(item)
            NotificationManager.shared.scheduleMovieNotification(item: item)
        }
    }
    
    private func refreshTVShow(tmdbID: Int) async throws {
        let details = try await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
        
        var tvMazeID: Int?
        var mazeTime: String?
        var mazeName: String?
        var mazeFullDate: Date?
        var actualService: String?
        var actualTimezone: String?
        
        var allTVMazeEpisodes: [TVMazeEpisode] = []
        if let tvdbID = details.tvdbID {
            if let mID = try await APIClient.shared.lookupTVMazeID(tvdbID: tvdbID) {
                tvMazeID = mID
                if let (episode, timezone, service) = try? await APIClient.shared.fetchTVMazeSchedule(tvMazeID: mID), let schedule = episode {
                    mazeTime = schedule.airtime
                    mazeName = schedule.name
                    mazeFullDate = DateUtils.parseFullDate(dateString: schedule.airdate, timeString: schedule.airtime, airstamp: schedule.airstamp, timezone: timezone, serviceName: service, item: item)
                    actualService = service 
                    actualTimezone = timezone
                }
                if let fetched = try? await APIClient.shared.fetchTVMazeEpisodes(tvMazeID: mID) {
                    allTVMazeEpisodes = fetched
                }
            }
        }

        // Fetch all seasons' episodes in parallel
        var allSeasonsEpisodes: [Int: [TVEpisodeResult]] = [:]
        try await withThrowingTaskGroup(of: (Int, [TVEpisodeResult]).self) { group in
            for seasonBrief in details.seasons {
                group.addTask {
                    let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: seasonBrief.season_number)
                    return (seasonBrief.season_number, episodes)
                }
            }
            for try await (seasonNumber, episodes) in group {
                allSeasonsEpisodes[seasonNumber] = episodes
            }
        }

        // Fix Swift 6 concurrency warnings by shadowing with let (immutable copies)
        let finalAllSeasonsEpisodes = allSeasonsEpisodes
        let finalAllTVMazeEpisodes = allTVMazeEpisodes
        let finalTvMazeID = tvMazeID
        let finalMazeTime = mazeTime
        let finalMazeName = mazeName
        let finalMazeFullDate = mazeFullDate
        let finalActualService = actualService
        let finalActualTimezone = actualTimezone

        await MainActor.run {
            item.releaseDate = DateUtils.parseDate(details.firstAirDate)
            item.lastUpdated = Date()
            
            let tvDetails = item.tvShowDetails ?? TVShowDetails(tmdbID: tmdbID)
            tvDetails.voteAverage = details.voteAverage
            tvDetails.nextEpisodeDate = finalMazeFullDate ?? DateUtils.parseEpisodeDate(details.nextEpisodeDate, serviceName: finalActualService ?? tvDetails.network, for: tvDetails)
            tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
            tvDetails.nextSeasonNumber = details.nextSeasonNumber
            tvDetails.tvMazeID = finalTvMazeID
            tvDetails.nextEpisodeTime = finalMazeTime
            tvDetails.network = finalActualService ?? tvDetails.network
            tvDetails.timezone = finalActualTimezone ?? tvDetails.timezone
            
            // Update Cast
            tvDetails.cast.removeAll()
            for c in details.cast {
                let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                tvDetails.cast.append(CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order))
            }
            
            if let tmdbNextDateString = details.nextEpisodeDate, let tmdbNextDate = DateUtils.parseDate(tmdbNextDateString) {
                if let mazeFullDate = finalMazeFullDate, Calendar.current.isDate(mazeFullDate, inSameDayAs: tmdbNextDate) {
                    tvDetails.nextEpisodeName = finalMazeName
                }
            }
            
            for seasonBrief in details.seasons {
                let existingSeason = tvDetails.seasons.first(where: { $0.seasonNumber == seasonBrief.season_number })
                let season: TVSeason
                if let s = existingSeason {
                    s.episodeCount = seasonBrief.episode_count
                    s.name = seasonBrief.name
                    s.airDate = seasonBrief.air_date
                    s.tvShowDetails = tvDetails
                    season = s
                } else {
                    let newSeason = TVSeason(seasonNumber: seasonBrief.season_number, name: seasonBrief.name, episodeCount: seasonBrief.episode_count, airDate: seasonBrief.air_date)
                    newSeason.tvShowDetails = tvDetails
                    tvDetails.seasons.append(newSeason)
                    season = newSeason
                }
                
                // Update episodes for this season from the pre-fetched data
                if let episodes = finalAllSeasonsEpisodes[season.seasonNumber] {
                    for ep in episodes {
                        let matchingMaze = finalAllTVMazeEpisodes.first { $0.season == season.seasonNumber && $0.number == ep.episodeNumber }
                        let airstamp = matchingMaze?.airstamp
                        
                        if let existingEpisode = season.episodes.first(where: { $0.episodeNumber == ep.episodeNumber }) {
                            existingEpisode.name = ep.name
                            existingEpisode.overview = ep.overview
                            existingEpisode.airDate = ep.airDate
                            existingEpisode.airstamp = airstamp
                            existingEpisode.runtime = ep.runtime
                            existingEpisode.season = season
                        } else {
                            let newEpisode = TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: season.seasonNumber, name: ep.name, overview: ep.overview, airDate: ep.airDate, airstamp: airstamp, runtime: ep.runtime)
                            newEpisode.season = season
                            season.episodes.append(newEpisode)
                        }
                    }
                }
            }
            item.tvShowDetails = tvDetails
            SpotlightManager.shared.indexItem(item)
            NotificationManager.shared.scheduleTVNotification(item: item)
            updateThemeColor()
        }
    }
    
    func markAllAsWatched() {
        if let tv = item.tvShowDetails {
            let seasonIDs = tv.seasons.map { $0.persistentModelID }
            let tmdbID = tv.tmdbID
            
            Task {
                for seasonID in seasonIDs {
                    await fetchEpisodesIfNeeded(for: seasonID, tmdbID: tmdbID)
                }
                
                await MainActor.run {
                    if let tv = self.item.tvShowDetails {
                        for season in tv.seasons {
                            for episode in season.episodes {
                                episode.isWatched = true
                            }
                        }
                        self.checkOverallCompletion()
                    }
                }
            }
        }
    }
    
    private func fetchEpisodesIfNeeded(for seasonID: PersistentIdentifier, tmdbID: Int) async {
        if let tv = self.item.tvShowDetails, 
           let season = tv.seasons.first(where: { $0.persistentModelID == seasonID }),
           season.episodes.isEmpty {
            do {
                let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: season.seasonNumber)
                await MainActor.run {
                    for ep in episodes {
                        let newEpisode = TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: season.seasonNumber, name: ep.name, overview: ep.overview, airDate: ep.airDate, airstamp: nil, runtime: ep.runtime)
                        newEpisode.season = season
                        season.episodes.append(newEpisode)
                        newEpisode.isWatched = true
                    }
                    self.checkOverallCompletion()
                }
            } catch {
                print("❌ Error fetching episodes in markAllAsWatched: \(error)")
            }
        }
    }
    
    func checkOverallCompletion() {
        guard let tv = item.tvShowDetails else { return }
        let totalEpisodes = tv.numberOfEpisodes ?? 0
        let watchedEpisodes = tv.seasons.reduce(0) { $0 + $1.episodes.filter { $0.isWatched }.count }
        
        withAnimation {
            if totalEpisodes > 0 {
                if watchedEpisodes >= totalEpisodes {
                    item.state = .completed
                    NotificationManager.shared.cancelNotification(for: item)
                } else if watchedEpisodes > 0 {
                    item.state = .active
                } else {
                    item.state = .wishlist
                }
            }
        }
    }
    
    private func fetchEpisodesForSeason(_ season: TVSeason, tmdbID: Int, tvMazeEpisodes: [TVMazeEpisode] = []) async {
        let seasonNumber = season.seasonNumber
        let seasonID = season.persistentModelID
        let finalTvMazeEpisodes = tvMazeEpisodes

        do {
            let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: seasonNumber)
            await MainActor.run {
                // Find the season again on MainActor
                guard let tv = self.item.tvShowDetails,
                      let seasonOnMain = tv.seasons.first(where: { $0.persistentModelID == seasonID }) else { return }
                
                for ep in episodes {
                    let matchingMaze = finalTvMazeEpisodes.first { $0.season == seasonNumber && $0.number == ep.episodeNumber }
                    let airstamp = matchingMaze?.airstamp
                    
                    if let existingEpisode = seasonOnMain.episodes.first(where: { $0.episodeNumber == ep.episodeNumber }) {
                        existingEpisode.name = ep.name
                        existingEpisode.overview = ep.overview
                        existingEpisode.airDate = ep.airDate
                        existingEpisode.airstamp = airstamp
                        existingEpisode.runtime = ep.runtime
                        existingEpisode.season = seasonOnMain
                    } else {
                        let newEpisode = TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: seasonNumber, name: ep.name, overview: ep.overview, airDate: ep.airDate, airstamp: airstamp, runtime: ep.runtime)
                        newEpisode.season = seasonOnMain
                        seasonOnMain.episodes.append(newEpisode)
                    }
                }
            }
        } catch {
            print("❌ Error fetching episodes: \(error)")
        }
    }
    
    func nextEpisodeLabel(for date: Date, hideDate: Bool = false) -> String {
        let dateString = date.formatted(date: .abbreviated, time: .shortened)
        guard let tv = item.tvShowDetails else { return hideDate ? "" : dateString }
        
        let allEpisodes = tv.seasons.flatMap { $0.episodes }
        
        let matchingEpisodes = allEpisodes.filter { ep in
            if let epDate = ep.airDateAsDate {
                return abs(epDate.timeIntervalSince(date)) < 60 
            }
            return false
        }
        
        let sortedMatching = matchingEpisodes
            .filter { !$0.isWatched }
            .sorted { (ep1, ep2) in
                if ep1.seasonNumber == ep2.seasonNumber {
                    return ep1.episodeNumber < ep2.episodeNumber
                }
                return ep1.seasonNumber < ep2.seasonNumber
            }
        
        let finalEpisode = sortedMatching.first ?? matchingEpisodes.sorted { (ep1, ep2) in
            if ep1.seasonNumber == ep2.seasonNumber {
                return ep1.episodeNumber < ep2.episodeNumber
            }
            return ep1.seasonNumber < ep2.seasonNumber
        }.first
        
        let dateSuffix = hideDate ? "" : " (\(dateString))"
        
        if let ep = finalEpisode {
            let seasonItem = tv.seasons.first(where: { $0.seasonNumber == ep.seasonNumber })
            let isFullSeasonDrop = seasonItem != nil && matchingEpisodes.count == seasonItem!.episodeCount && matchingEpisodes.count > 1
            
            if isFullSeasonDrop {
                return "Full Season \(ep.seasonNumber) 🍿\(dateSuffix)"
            }
            
            let title = ep.name.isEmpty ? "TBA" : ep.name
            return "S\(ep.seasonNumber), E\(ep.episodeNumber): \(title)\(dateSuffix)"
        }
        
        if let s = tv.nextSeasonNumber, let e = tv.nextEpisodeNumber {
            return "S\(s), E\(e): \(tv.nextEpisodeName ?? "TBA")\(dateSuffix)"
        }
        
        return hideDate ? "" : dateString
    }
}
