import SwiftUI
import SwiftData

struct DetailView: View {
    @Bindable var item: MediaItem
    @State private var isRefreshing = false
    
    private var needsUpdate: Bool {
        guard let lastUpdated = item.lastUpdated else { return true }
        // Update if more than 24 hours (86400 seconds) have passed
        return Date().timeIntervalSince(lastUpdated) > 86400
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 30) {
                    if let urlString = item.posterURL, let url = URL(string: urlString) {
                        CachedImage(url: url) {
                            Rectangle().fill(Color.secondary.opacity(0.1))
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 240)
                        .cornerRadius(12)
                        .shadow(radius: 10)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text(item.title)
                            .font(.system(size: 34, weight: .bold))
                        
                        HStack {
                            Text(item.type?.rawValue ?? "")
                                .padding(6)
                                .background(Color.accentColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            
                            Picker("Status", selection: $item.state) {
                                ForEach(MediaState.allCases, id: \.self) { state in
                                    Text(state.displayName).tag(state as MediaState?)
                                }
                            }
                            .pickerStyle(.menu)
                            .onChange(of: item.state) { oldValue, newValue in
                                if newValue == .completed {
                                    NotificationManager.shared.cancelNotification(for: item)
                                    markAllAsWatched()
                                }
                            }
                            
                            if item.isUpcoming {
                                Text("Upcoming")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        if let movie = item.movieDetails {
                            if let releaseDate = item.releaseDate {
                                Text("Release Date: \(releaseDate.formatted(date: .long, time: .omitted))")
                            }
                            
                            if let runtime = movie.runtime {
                                Text("Runtime: \(DateUtils.formatRuntime(runtime))")
                            }
                            Text("Genres: \(movie.genres.joined(separator: ", "))")
                        }
                        
                        if let tv = item.tvShowDetails {
                            if let next = tv.nextEpisodeDate {
                                Text("Next Episode: \(next.formatted(date: .abbreviated, time: .shortened))")
                                    .foregroundStyle(Color.accentColor)
                            }
                            Text("Status: \(tv.status ?? "Unknown")")
                            if let seasons = tv.numberOfSeasons {
                                Text("Seasons: \(seasons)")
                            }
                            if let episodes = tv.numberOfEpisodes {
                                Text("Episodes: \(episodes)")
                            }
                        }
                        
                        if let book = item.bookDetails {
                            Text("Author(s): \(book.authors.joined(separator: ", "))")
                            if let pages = book.pageCount {
                                Text("Pages: \(pages)")
                            }
                        }
                        
                        if (item.type == .movie && item.movieDetails?.genres.isEmpty != false) || (item.type == .tvShow && item.tvShowDetails?.status == nil) {
                            if APIClient.shared.tmdbApiKey.isEmpty {
                                Text("Please add your TMDB API Key in Settings to see more details.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Divider().padding(.vertical, 5)
                        
                        Text("Overview")
                            .font(.headline)
                        
                        Text(item.overview)
                            .font(.body)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                    }
                }
                
                Divider()
                
                if let tv = item.tvShowDetails {
                    Divider()
                    TVTrackingView(tvDetails: tv, onWatchedToggle: {
                        checkOverallCompletion()
                    })
                }
                
                Divider()
                
                HStack(spacing: 40) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("My Rating")
                            .font(.headline)
                        
                        HStack(spacing: 20) {
                            Button {
                                item.isLiked = true
                            } label: {
                                Image(systemName: item.isLiked == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .foregroundStyle(item.isLiked == true ? .green : .primary)
                                Text("Like")
                            }
                            .buttonStyle(.bordered)
                            
                            Button {
                                item.isLiked = false
                            } label: {
                                Image(systemName: item.isLiked == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                                    .foregroundStyle(item.isLiked == false ? .red : .primary)
                                Text("Dislike")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    let voteAverage: Double? = item.movieDetails?.voteAverage ?? item.tvShowDetails?.voteAverage
                    if let rating = voteAverage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Community Rating")
                                .font(.headline)
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                Text(String(format: "%.1f / 10", rating))
                                    .font(.title3.bold())
                            }
                        }
                    }
                }
            }
            .padding(30)
        }
        .navigationTitle("Details")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    forceRefresh()
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
            fetchMissingDetails()
        }
    }
    
    private func forceRefresh() {
        isRefreshing = true
        let itemType = item.type
        let itemID = item.id
        
        Task {
            if itemType == .movie {
                if let tmdbID = Int(itemID) {
                    let details = try? await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                    if let details = details {
                        await MainActor.run {
                            item.releaseDate = DateUtils.parseDate(details.releaseDate)
                            item.movieDetails = MovieDetails(tmdbID: tmdbID, runtime: details.runtime, genres: details.genres, voteAverage: details.voteAverage)
                            item.lastUpdated = Date()
                            try? item.modelContext?.save()
                            NotificationManager.shared.scheduleMovieNotification(item: item)
                            isRefreshing = false
                        }
                    } else {
                        await MainActor.run { isRefreshing = false }
                    }
                }
            } else if itemType == .tvShow {
                if let tmdbID = Int(itemID) {
                    let details = try? await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
                    if let details = details {
                        // Perform additional async lookups BEFORE MainActor.run
                        var tvMazeID: Int?
                        var mazeTime: String?
                        var mazeName: String?
                        var mazeFullDate: Date?
                        
                        if let tvdbID = try? await APIClient.shared.fetchTVExternalIDs(tmdbID: tmdbID) {
                            if let mID = try? await APIClient.shared.lookupTVMazeID(tvdbID: tvdbID) {
                                tvMazeID = mID
                                if let (episode, timezone, service) = try? await APIClient.shared.fetchTVMazeSchedule(tvMazeID: mID), let schedule = episode {
                                    mazeTime = schedule.airtime
                                    mazeName = schedule.name
                                    mazeFullDate = DateUtils.parseFullDate(dateString: schedule.airdate, timeString: schedule.airtime, airstamp: schedule.airstamp, timezone: timezone, serviceName: service, item: item)
                                    tvMazeID = mID // redundancy
                                    // We will store the service name and timezone in tvDetails inside MainActor.run
                                    let actualService = service 
                                    let actualTimezone = timezone
                                    
                                    await MainActor.run {
                                        if let tvDetails = item.tvShowDetails {
                                            tvDetails.network = actualService
                                            tvDetails.timezone = actualTimezone
                                        }
                                    }
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
                            tvDetails.nextEpisodeDate = mazeFullDate ?? DateUtils.parseDate(details.nextEpisodeDate)
                            tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
                            tvDetails.nextSeasonNumber = details.nextSeasonNumber
                            tvDetails.tvMazeID = tvMazeID
                            tvDetails.nextEpisodeTime = mazeTime
                            
                            if let tmdbNextDateString = details.nextEpisodeDate, let tmdbNextDate = DateUtils.parseDate(tmdbNextDateString) {
                                if let mazeFullDate = mazeFullDate, Calendar.current.isDate(mazeFullDate, inSameDayAs: tmdbNextDate) {
                                    tvDetails.nextEpisodeName = mazeName
                                }
                            }
                            
                            // Merge seasons
                            for seasonBrief in details.seasons {
                                if let existingSeason = tvDetails.seasons.first(where: { $0.seasonNumber == seasonBrief.season_number }) {
                                    existingSeason.episodeCount = seasonBrief.episode_count
                                    existingSeason.name = seasonBrief.name
                                    existingSeason.airDate = seasonBrief.air_date
                                } else {
                                    tvDetails.seasons.append(TVSeason(seasonNumber: seasonBrief.season_number, name: seasonBrief.name, episodeCount: seasonBrief.episode_count, airDate: seasonBrief.air_date))
                                }
                            }
                            item.tvShowDetails = tvDetails
                            try? item.modelContext?.save()
                            NotificationManager.shared.scheduleTVNotification(item: item)
                        }
                        
                        // Fetch episodes for all seasons to get runtimes
                        if let tv = item.tvShowDetails {
                            for season in tv.seasons {
                                await fetchEpisodesForSeason(season, tmdbID: tmdbID)
                            }
                        }
                        
                        await MainActor.run { isRefreshing = false }
                    } else {
                        await MainActor.run { isRefreshing = false }
                    }
                }
            } else {
                await MainActor.run { isRefreshing = false }
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
    
    private func fetchEpisodesForSeason(_ season: TVSeason, tmdbID: Int) async {
        do {
            let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: season.seasonNumber)
            await MainActor.run {
                for ep in episodes {
                    if let existingEpisode = season.episodes.first(where: { $0.episodeNumber == ep.episodeNumber }) {
                        // Update metadata but PRESERVE isWatched
                        existingEpisode.name = ep.name
                        existingEpisode.overview = ep.overview
                        existingEpisode.airDate = ep.airDate
                        existingEpisode.runtime = ep.runtime
                        existingEpisode.season = season
                    } else {
                        // Add new episode
                        let newEpisode = TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: season.seasonNumber, name: ep.name, overview: ep.overview, airDate: ep.airDate, runtime: ep.runtime)
                        newEpisode.season = season
                        season.episodes.append(newEpisode)
                    }
                }
                try? item.modelContext?.save()
            }
        } catch {
            print("❌ Error fetching episodes: \(error)")
        }
    }
    
    private func fetchMissingDetails() {
        // If critical data is missing, we fetch immediately. 
        // If we have data, we only fetch if it's been 24h.
        let hasData = item.movieDetails != nil || (item.type == .tvShow && (item.tvShowDetails != nil && item.tvShowDetails?.status != nil))
        if hasData && !needsUpdate { return }
        
        let itemType = item.type
        let itemID = item.id
        
        Task {
            if itemType == .movie {
                if let tmdbID = Int(itemID) {
                    let details = try? await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                    if let details = details {
                        await MainActor.run {
                            item.releaseDate = DateUtils.parseDate(details.releaseDate)
                            item.movieDetails = MovieDetails(tmdbID: tmdbID, runtime: details.runtime, genres: details.genres, voteAverage: details.voteAverage)
                            item.lastUpdated = Date()
                            try? item.modelContext?.save()
                            NotificationManager.shared.scheduleMovieNotification(item: item)
                        }
                    }
                }
            } else if itemType == .tvShow {
                if let tmdbID = Int(itemID) {
                    let details = try? await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
                    if let details = details {
                        // Perform additional async lookups BEFORE MainActor.run
                        var tvMazeID: Int?
                        var mazeTime: String?
                        var mazeName: String?
                        var mazeFullDate: Date?
                        
                        if let tvdbID = try? await APIClient.shared.fetchTVExternalIDs(tmdbID: tmdbID) {
                            if let mID = try? await APIClient.shared.lookupTVMazeID(tvdbID: tvdbID) {
                                tvMazeID = mID
                                if let (episode, timezone, service) = try? await APIClient.shared.fetchTVMazeSchedule(tvMazeID: mID), let schedule = episode {
                                    mazeTime = schedule.airtime
                                    mazeName = schedule.name
                                    mazeFullDate = DateUtils.parseFullDate(dateString: schedule.airdate, timeString: schedule.airtime, airstamp: schedule.airstamp, timezone: timezone, serviceName: service, item: item)
                                    tvMazeID = mID // redundancy
                                    // We will store the service name and timezone in tvDetails inside MainActor.run
                                    let actualService = service 
                                    let actualTimezone = timezone
                                    
                                    await MainActor.run {
                                        if let tvDetails = item.tvShowDetails {
                                            tvDetails.network = actualService
                                            tvDetails.timezone = actualTimezone
                                        }
                                    }
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
                            tvDetails.nextEpisodeDate = mazeFullDate ?? DateUtils.parseDate(details.nextEpisodeDate)
                            tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
                            tvDetails.nextSeasonNumber = details.nextSeasonNumber
                            tvDetails.tvMazeID = tvMazeID
                            tvDetails.nextEpisodeTime = mazeTime
                            
                            if let tmdbNextDateString = details.nextEpisodeDate, let tmdbNextDate = DateUtils.parseDate(tmdbNextDateString) {
                                if let mazeFullDate = mazeFullDate, Calendar.current.isDate(mazeFullDate, inSameDayAs: tmdbNextDate) {
                                    tvDetails.nextEpisodeName = mazeName
                                }
                            }
                            
                            // Merge seasons
                            for seasonBrief in details.seasons {
                                if let existingSeason = tvDetails.seasons.first(where: { $0.seasonNumber == seasonBrief.season_number }) {
                                    existingSeason.episodeCount = seasonBrief.episode_count
                                    existingSeason.name = seasonBrief.name
                                    existingSeason.airDate = seasonBrief.air_date
                                } else {
                                    tvDetails.seasons.append(TVSeason(seasonNumber: seasonBrief.season_number, name: seasonBrief.name, episodeCount: seasonBrief.episode_count, airDate: seasonBrief.air_date))
                                }
                            }
                            item.tvShowDetails = tvDetails
                            try? item.modelContext?.save()
                            NotificationManager.shared.scheduleTVNotification(item: item)
                        }
                    }
                }
            }
        }
    }
}

struct TVTrackingView: View {
    @Bindable var tvDetails: TVShowDetails
    var onWatchedToggle: () -> Void
    @State private var selectedSeasonNumber: Int = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Episodes & Tracking")
                    .font(.headline)
                Spacer()
                
                Picker("Season", selection: $selectedSeasonNumber) {
                    ForEach(tvDetails.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber })) { season in
                        Text("Season \(season.seasonNumber)").tag(season.seasonNumber)
                    }
                }
                .frame(width: 150)
            }
            
            if let selectedSeason = tvDetails.seasons.first(where: { $0.seasonNumber == selectedSeasonNumber }) {
                let isSeasonFinished = !selectedSeason.episodes.isEmpty && selectedSeason.episodes.allSatisfy { $0.isWatched }
                
                VStack(alignment: .leading) {
                    HStack {
                        Text(selectedSeason.name)
                            .font(.subheadline.bold())
                        Spacer()
                        
                        if selectedSeason.episodeCount > 0 {
                            Button(isSeasonFinished ? "Unmark Season" : "Mark Season Finished") {
                                if isSeasonFinished {
                                    unmarkSeasonWatched(selectedSeason)
                                } else {
                                    markSeasonWatched(selectedSeason)
                                }
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        } else {
                            Text("Upcoming Season")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 5)
                    
                    ScrollView(.vertical, showsIndicators: true) {
                        if selectedSeason.episodeCount == 0 {
                            ContentUnavailableView("No episodes announced yet", systemImage: "calendar.badge.clock")
                                .padding()
                        } else if selectedSeason.episodes.isEmpty {
                            ProgressView("Loading Episodes...")
                                .padding()
                                .onAppear {
                                    Task { await fetchEpisodes(for: selectedSeason) }
                                }
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 15)], spacing: 15) {
                                ForEach(selectedSeason.episodes.sorted(by: { $0.episodeNumber < $1.episodeNumber })) { episode in
                                    EpisodeCard(episode: episode, onWatchedToggle: onWatchedToggle)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .frame(minHeight: 150, maxHeight: 400)
                }
            }
        }
        .onAppear {
            if let firstSeason = tvDetails.seasons.sorted(by: { $0.seasonNumber < $1.seasonNumber }).first {
                selectedSeasonNumber = firstSeason.seasonNumber
            }
        }
    }
    
    private func markSeasonWatched(_ season: TVSeason) {
        if season.episodes.isEmpty {
            Task {
                await fetchEpisodes(for: season)
                await MainActor.run {
                    withAnimation {
                        for episode in season.episodes {
                            episode.isWatched = true
                        }
                        onWatchedToggle()
                    }
                }
            }
        } else {
            withAnimation {
                for episode in season.episodes {
                    episode.isWatched = true
                }
                onWatchedToggle()
            }
        }
    }
    
    private func unmarkSeasonWatched(_ season: TVSeason) {
        withAnimation {
            for episode in season.episodes {
                episode.isWatched = false
            }
            onWatchedToggle()
        }
    }
    
    private func fetchEpisodes(for season: TVSeason) async {
        do {
            let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tvDetails.tmdbID, seasonNumber: season.seasonNumber)
            await MainActor.run {
                season.episodes = episodes.map { ep in
                    TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: season.seasonNumber, name: ep.name, overview: ep.overview, airDate: ep.airDate, runtime: ep.runtime)
                }
            }
        } catch {
            print("Error fetching episodes: \(error)")
        }
    }
}

struct EpisodeCard: View {
    @Bindable var episode: TVEpisode
    var onWatchedToggle: () -> Void
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                episode.isWatched.toggle()
                onWatchedToggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text("\(episode.episodeNumber)")
                        .font(.system(.title3, design: .rounded).bold())
                        .foregroundStyle(episode.isWatched ? Color.accentColor : .secondary)
                    
                    Spacer()
                    
                    if episode.isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                
                Text(episode.name)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(height: 35, alignment: .topLeading)
                
                HStack {
                    if let airDate = episode.airDate {
                        Text(formatShortAirDate(airDate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    if let runtime = episode.runtime, runtime > 0 {
                        Spacer()
                        Text(DateUtils.formatRuntime(runtime))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 160)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(episode.isWatched ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formatShortAirDate(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        
        guard let date = inputFormatter.date(from: dateString) else { return dateString }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
