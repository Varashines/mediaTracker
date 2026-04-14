import SwiftUI
import SwiftData

struct DetailView: View {
    @Bindable var item: MediaItem
    @State private var isRefreshing = false
    @State private var themeColor: Color = Color.secondary.opacity(0.1)
    
    private var needsUpdate: Bool {
        guard let lastUpdated = item.lastUpdated else { return true }
        return Date().timeIntervalSince(lastUpdated) > 86400
    }
    
    private var nextText: String? {
        guard let date = item.nextAiringDate else { return nil }
        let isPast = date < Date()
        if isPast {
            if item.type == .movie {
                return "Available Now"
            }
            let label = nextEpisodeLabel(for: date, hideDate: true)
            return label.isEmpty ? "Available Now" : "Available Now: \(label)"
        }
        if item.type == .movie {
            return "Releases on \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Next: \(nextEpisodeLabel(for: date, hideDate: false))"
    }
    
    var body: some View {
        ZStack {
            // Dynamic Background Gradient
            LinearGradient(
                gradient: Gradient(colors: [themeColor.opacity(0.15), Color(NSColor.windowBackgroundColor)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Optimized Header Section
                    MediaHeaderView(item: item, themeColor: themeColor, nextEpisodeText: nextText) { newState in
                        if newState == .completed {
                            NotificationManager.shared.cancelNotification(for: item)
                            markAllAsWatched()
                        }
                    }
                    .onAppear {
                        // Extract theme color if not already set or refreshing
                        updateThemeColor()
                    }
                    
                    if (item.type == .movie && item.movieDetails?.genres.isEmpty != false) || (item.type == .tvShow && item.tvShowDetails?.status == nil) {
                        if !APIClient.shared.isTMDBConfigured {
                            Text("Please add your TMDB API Key in Settings to see more details.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if let cast = (item.movieDetails?.cast ?? item.tvShowDetails?.cast), !cast.isEmpty {
                        Divider()
                        CastSectionView(cast: cast)
                    }
                    
                    if let tv = item.tvShowDetails {
                        Divider()
                        TVTrackingView(tvDetails: tv, onWatchedToggle: {
                            checkOverallCompletion()
                        })
                    }
                    
                    Divider()
                    
                    RatingSection(item: item)
                }
                .padding(30)
            }
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refreshData(force: true)
                    } label: {
                        if isRefreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isRefreshing)
                }
            }
            .onAppear {
                refreshData()
            }
            .tint(themeColor) // Maintain accent color based on poster
        }
    }
    
    private func updateThemeColor() {
        guard let urlString = item.posterURL, let url = URL(string: urlString) else { return }
        if let cachedImage = ImageCache.shared.get(forKey: url.absoluteString) {
            themeColor = ColorExtractor.dominantColor(from: cachedImage)
        }
    }
    
    private func refreshData(force: Bool = false) {
        let hasData = item.movieDetails != nil || (item.type == .tvShow && (item.tvShowDetails != nil && item.tvShowDetails?.status != nil))
        if !force && hasData && !needsUpdate { return }
        
        isRefreshing = true
        let itemType = item.type
        let itemID = item.id
        
        Task {
            defer { Task { @MainActor in isRefreshing = false } }
            do {
                if itemType == .movie, let tmdbID = Int(itemID) {
                    try await refreshMovie(tmdbID: tmdbID)
                } else if itemType == .tvShow, let tmdbID = Int(itemID) {
                    try await refreshTVShow(tmdbID: tmdbID)
                }
                updateThemeColor()
            } catch {
                print("❌ Refresh error: \(error)")
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

        await MainActor.run {
            item.releaseDate = DateUtils.parseDate(details.firstAirDate)
            item.lastUpdated = Date()
            
            let tvDetails = item.tvShowDetails ?? TVShowDetails(tmdbID: tmdbID)
            tvDetails.status = details.status
            tvDetails.numberOfSeasons = details.seasonsCount
            tvDetails.numberOfEpisodes = details.episodesCount
            tvDetails.voteAverage = details.voteAverage
            tvDetails.nextEpisodeDate = mazeFullDate ?? DateUtils.parseEpisodeDate(details.nextEpisodeDate, serviceName: actualService ?? tvDetails.network, for: tvDetails)
            tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
            tvDetails.nextSeasonNumber = details.nextSeasonNumber
            tvDetails.tvMazeID = tvMazeID
            tvDetails.nextEpisodeTime = mazeTime
            tvDetails.network = actualService ?? tvDetails.network
            tvDetails.timezone = actualTimezone ?? tvDetails.timezone
            
            // Update Cast
            tvDetails.cast.removeAll()
            for c in details.cast {
                let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                tvDetails.cast.append(CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order))
            }
            
            if let tmdbNextDateString = details.nextEpisodeDate, let tmdbNextDate = DateUtils.parseDate(tmdbNextDateString) {
                if let mazeFullDate = mazeFullDate, Calendar.current.isDate(mazeFullDate, inSameDayAs: tmdbNextDate) {
                    tvDetails.nextEpisodeName = mazeName
                }
            }
            
            for seasonBrief in details.seasons {
                if let existingSeason = tvDetails.seasons.first(where: { $0.seasonNumber == seasonBrief.season_number }) {
                    existingSeason.episodeCount = seasonBrief.episode_count
                    existingSeason.name = seasonBrief.name
                    existingSeason.airDate = seasonBrief.air_date
                    existingSeason.tvShowDetails = tvDetails
                } else {
                    let newSeason = TVSeason(seasonNumber: seasonBrief.season_number, name: seasonBrief.name, episodeCount: seasonBrief.episode_count, airDate: seasonBrief.air_date)
                    newSeason.tvShowDetails = tvDetails
                    tvDetails.seasons.append(newSeason)
                }
            }
            item.tvShowDetails = tvDetails
            SpotlightManager.shared.indexItem(item)
            NotificationManager.shared.scheduleTVNotification(item: item)
        }
        
        if let tv = item.tvShowDetails {
            await withTaskGroup(of: Void.self) { group in
                for season in tv.seasons {
                    group.addTask {
                        await fetchEpisodesForSeason(season, tmdbID: tmdbID, tvMazeEpisodes: allTVMazeEpisodes)
                    }
                }
            }
        }
    }
    
    private func markAllAsWatched() {
        if let tv = item.tvShowDetails {
            for season in tv.seasons {
                if season.episodes.isEmpty {
                    Task {
                        await fetchEpisodesForSeason(season, tmdbID: tv.tmdbID)
                        await MainActor.run {
                            for episode in season.episodes {
                                episode.isWatched = true
                            }
                            checkOverallCompletion()
                        }
                    }
                } else {
                    for episode in season.episodes {
                        episode.isWatched = true
                    }
                }
            }
        }
    }
    
    private func checkOverallCompletion() {
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
        do {
            let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: season.seasonNumber)
            await MainActor.run {
                for ep in episodes {
                    let matchingMaze = tvMazeEpisodes.first { $0.season == season.seasonNumber && $0.number == ep.episodeNumber }
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
        } catch {
            print("❌ Error fetching episodes: \(error)")
        }
    }
    
    private func nextEpisodeLabel(for date: Date, hideDate: Bool = false) -> String {
        let dateString = date.formatted(date: .abbreviated, time: .shortened)
        guard let tv = item.tvShowDetails else { return hideDate ? "" : dateString }
        
        let allEpisodes = tv.seasons.flatMap { $0.episodes }
        
        // Find all episodes matching the nextAiringDate precisely
        let matchingEpisodes = allEpisodes.filter { ep in
            if let epDate = ep.airDateAsDate {
                // Allow a small tolerance (1 minute) for floating point comparison
                return abs(epDate.timeIntervalSince(date)) < 60 
            }
            return false
        }
        
        // Sort them to prioritize the earliest unwatched episode (lowest season/episode number)
        let sortedMatching = matchingEpisodes
            .filter { !$0.isWatched } // Only consider unwatched ones if there's a mix
            .sorted { (ep1, ep2) in
                if ep1.seasonNumber == ep2.seasonNumber {
                    return ep1.episodeNumber < ep2.episodeNumber
                }
                return ep1.seasonNumber < ep2.seasonNumber
            }
        
        // Fallback to watched if all matching are watched (rare edge case)
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
