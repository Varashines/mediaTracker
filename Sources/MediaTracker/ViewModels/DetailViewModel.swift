import SwiftUI
import SwiftData

@Observable @MainActor
class DetailViewModel {
    var item: MediaItem
    var isRefreshing = false
    var themeColor: Color = Color.secondary.opacity(0.1)
    
    // Phase 5 Performance: Cache scheme-aware colors to avoid per-frame math in MeshGradient
    var vibrantThemeColor: Color = .clear
    var recommendations: [MooreMetricsRecommendation] = []
    var isLoadingRecommendations = false
    var trailerKey: String?
    var watchProviders: [WatchProviderResult] = []
    var posterOptions: [String] = []
    var logoOptions: [String] = []
    var debugSelectedTraits: [String] = []
    private var _nextEpisodeToWatch: TVEpisode?? = nil
    private var _darkerThemeColor: Color = .clear
    private var _lighterThemeColor: Color = .clear
    private var _highContrastAccent: Color = .primary
    private var _luminousAccent: Color = .clear
    
    init(item: MediaItem) {
        self.item = item
        trailerKey = item.cachedTrailerKey
        updateThemeColor()
    }
    
    var needsUpdate: Bool {
        guard let lastUpdated = item.lastUpdated else { return true }
        
        // Active TV shows should check for updates every 24 hours
        if item.type == .tvShow && item.state == .active {
            return Date().timeIntervalSince(lastUpdated) > TimeInterval.secondsInDay
        }
        
        // Maintenance rule for TV shows (30 days)
        if item.type == .tvShow {
            return item.requiresMaintenanceRefresh
        }
        
        // Default 24h for movies
        return Date().timeIntervalSince(lastUpdated) > TimeInterval.secondsInDay
    }
    
    func updateThemeColor() {
        guard !SleepManager.shared.isAsleep else { return }

        // Priority 1: Pre-calculated Poster Color from SwiftData
        if let hex = item.themeColorHex,
           let cachedColor = Color(hex: hex.contains("|") ? String(hex.split(separator: "|")[0]) : hex) {
            self.themeColor = cachedColor
            self.recalculateVibrantPalette()
            return
        }

        // Priority 2: Network/Studio Theme Color (in-memory cache — no SQLite)
        if let networkName = item.cachedNetwork {
            let first = networkName.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? networkName
            if let netColor = NetworkThemeManager.shared.color(for: first) {
                self.themeColor = netColor
                self.recalculateVibrantPalette()
                return
            }
        }

        // Priority 3: Neutral fallback (never use global accent)
        self.themeColor = Color.secondary.opacity(0.15)
        self.recalculateVibrantPalette()
    }

    private func recalculateVibrantPalette() {
        #if os(macOS)
        let isDark = NSApp?.effectiveAppearance.name == .darkAqua
        #else
        let isDark = false
        #endif
        let scheme: ColorScheme = isDark ? .dark : .light
        self.vibrantThemeColor = themeColor.luminousAccent(colorScheme: scheme)
        self._highContrastAccent = themeColor.highContrastAccent(colorScheme: scheme)
        self._luminousAccent = themeColor.luminousAccent(colorScheme: scheme)
        
        let o = themeColor.oklch
        if o.c > 0.02 {
            _darkerThemeColor = Color.fromOKLCH(l: max(o.l - 0.12, 0.1), c: o.c, h: o.h)
            _lighterThemeColor = Color.fromOKLCH(l: min(o.l + 0.08, 0.95), c: o.c, h: o.h)
        } else {
            _darkerThemeColor = Color(white: max(o.l - 0.12, 0.1))
            _lighterThemeColor = Color(white: min(o.l + 0.08, 0.95))
        }
    }

    /// Darker variant of themeColor for mesh gradient corners.
    var darkerThemeColor: Color { _darkerThemeColor }

    /// Lighter variant of themeColor for mesh gradient edges.
    var lighterThemeColor: Color { _lighterThemeColor }

    /// Cached high-contrast accent (foreground color against themeColor backgrounds).
    var highContrastAccentColor: Color { _highContrastAccent }

    /// Cached luminous accent (brighter variant of themeColor for pill backgrounds).
    var luminousAccentColor: Color { _luminousAccent }

    var nextEpisodeToWatch: TVEpisode? {
        if let cached = _nextEpisodeToWatch { return cached }
        let result = computeNextEpisodeToWatch()
        _nextEpisodeToWatch = result
        return result
    }

    private func computeNextEpisodeToWatch() -> TVEpisode? {
        guard let tv = item.tvShowDetails else { return nil }
        let sortedSeasons = tv.seasons.sorted { $0.seasonNumber < $1.seasonNumber }
        for season in sortedSeasons where season.seasonNumber > 0 {
            let sortedEpisodes = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
            if let next = sortedEpisodes.first(where: { !$0.isWatched }) {
                return next
            }
        }
        return nil
    }
    
    private var needsOMDBData: Bool {
        let apiKey = UserDefaults.standard.string(forKey: UserDefaultsKeys.omdbAPIKey.rawValue) ?? ""
        guard !apiKey.isEmpty else { return false }
        
        if item.type == .movie {
            let md = item.movieDetails
            let missingContentRating = md?.contentRating == nil || md?.contentRating?.isEmpty == true
            let missingRT = md?.rottenTomatoesScore == nil
            return missingContentRating || missingRT
        } else {
            let td = item.tvShowDetails
            return td?.contentRating == nil || td?.contentRating?.isEmpty == true
        }
    }

    func refreshData(force: Bool = false) {
        guard item.modelContext != nil, !SleepManager.shared.isAsleep else { return }

        updateThemeColor()
        fetchTitleLogoIfNeeded()
        fetchPosterOptions()
        fetchWatchProvidersIfNeeded()

        let hasData = item.lastUpdated != nil

        if !force && DataService.shared.hasRefreshedThisSession(id: item.id) {
            return
        }

        if !force && hasData && !needsUpdate && !needsOMDBData { return }
        
        guard let context = item.modelContext else { return }

        isRefreshing = true
        let rawID = item.id

        Task { [weak self] in
            let backgroundService = BackgroundDataService(modelContainer: context.container)
            let success = await backgroundService.refreshSingleItem(id: rawID, force: force)

            await MainActor.run { [weak self] in
                guard let self = self, self.item.modelContext != nil else { return }
                if success {
                    self.refreshLocalItem()
                    DataService.shared.markAsRefreshedThisSession(id: rawID)
                }
                self.isRefreshing = false
            }
        }
    }

    func refreshLocalItem() {
        if let context = item.modelContext {
            context.processPendingChanges()
            let currentID = item.id
            let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == currentID })
            if let fresh = try? context.fetch(descriptor).first {
                self.item.cachedCreators = !fresh.cachedCreators.isEmpty ? fresh.cachedCreators : (fresh.tvShowDetails?.creators ?? [])
                self.item.cachedGenres = fresh.cachedGenres
                self.item.cachedNetwork = fresh.cachedNetwork
                self.item.cachedNetworkLogoPath = fresh.cachedNetworkLogoPath
                self.item.posterURL = fresh.posterURL ?? self.item.posterURL
                self.item.backdropURL = fresh.backdropURL ?? self.item.backdropURL
                self.item.themeColorHex = fresh.themeColorHex ?? self.item.themeColorHex
                self.item.themeColorSourceURL = fresh.themeColorSourceURL ?? self.item.themeColorSourceURL
                self.item.titleLogoURL = fresh.titleLogoURL ?? self.item.titleLogoURL
                if let logoURL = self.item.titleLogoURL, let url = URL(string: logoURL) {
                    ImageCache.shared.prewarmImages(urls: [url], targetSize: CGSize(width: 780, height: 185))
                }
            }
        }
        _nextEpisodeToWatch = nil
        item.syncCachedProperties(dirty: .all)
        item.tvShowDetails?.recalculateCachedProperties()
        trailerKey = item.cachedTrailerKey
        updateThemeColor()
        MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
    }

    /// Fetch title logo from TMDB independently of the main refresh cycle.
    /// This ensures logos are loaded even when `refreshData` returns early due to
    /// session debouncing or freshness guards.
    func fetchTitleLogoIfNeeded() {
        guard item.titleLogoURL == nil || logoOptions.isEmpty else { return }
        guard let tmdbString = item.id.split(separator: "_").last, let tmdbID = Int(tmdbString) else { return }

        let type = item.type
        let originalLanguage = item.cachedLanguage
        let defaultLogo = item.effectiveLogoURL

        logoTask?.cancel()
        logoTask = Task {
            do {
                var logos: [String]
                if type == .tvShow {
                    logos = try await APIClient.shared.fetchTVLogos(tmdbID: tmdbID, originalLanguage: originalLanguage)
                } else {
                    logos = try await APIClient.shared.fetchMovieLogos(tmdbID: tmdbID, originalLanguage: originalLanguage)
                }
                if !logos.isEmpty {
                    // Ensure the current effective logo is always first
                    if let current = defaultLogo {
                        logos.removeAll { $0 == current }
                        logos.insert(current, at: 0)
                    }
                    await MainActor.run {
                        self.item.titleLogoURL = logos.first
                        self.logoOptions = logos
                        if let context = self.item.modelContext {
                            SaveCoordinator.shared.requestSave(context)
                        }
                    }
                }
            } catch {
                AppLogger.warning("Logo fetch failed for \(type?.rawValue ?? "?") \(tmdbID): \(error)", logger: AppLogger.background)
            }
        }
    }

    /// Fetch alternative poster options from TMDB lazily.
    func fetchPosterOptions() {
        guard posterOptions.isEmpty else { return }
        guard let tmdbString = item.id.split(separator: "_").last, let tmdbID = Int(tmdbString) else { return }

        let type = item.type
        let originalLanguage = item.cachedLanguage
        let defaultPoster = item.effectivePosterURL

        posterTask?.cancel()
        posterTask = Task {
            do {
                var options: [String] = []
                if type == .tvShow {
                    options = try await APIClient.shared.fetchTVPosters(tmdbID: tmdbID, originalLanguage: originalLanguage)
                } else {
                    options = try await APIClient.shared.fetchMoviePosters(tmdbID: tmdbID, originalLanguage: originalLanguage)
                }
                // Ensure the current effective poster is always first in the list
                if let current = defaultPoster {
                    options.removeAll { $0 == current }
                    options.insert(current, at: 0)
                }
                await MainActor.run { [weak self] in
                    self?.posterOptions = options
                }
            } catch {
                AppLogger.warning("Poster options fetch failed for \(type?.rawValue ?? "?") \(tmdbID): \(error)", logger: AppLogger.background)
            }
        }
    }

    var isCustomPoster: Bool {
        item.customPosterURL != nil
    }

    func selectPoster(url: String) {
        guard item.modelContext != nil else { return }
        guard url != item.effectivePosterURL else { return }

        item.customPosterURL = url

        // Invalidate theme color so it re-extracts from the new poster
        if item.themeColorSourceURL == item.posterURL {
            item.themeColorSourceURL = url
            item.themeColorHex = nil
        }

        item.commitChange(dirty: [.badge])
        updateThemeColor()
        AppErrorState.shared.showToast("Poster updated", style: .success)
    }

    func resetToDefaultPoster() {
        guard item.modelContext != nil, item.customPosterURL != nil else { return }

        item.customPosterURL = nil

        // Restore theme color tracking to the default poster
        item.themeColorSourceURL = item.posterURL

        item.commitChange(dirty: [.badge])
        updateThemeColor()
        AppErrorState.shared.showToast("Poster reset to default", style: .success)
    }

    var isCustomLogo: Bool {
        item.customLogoURL != nil
    }

    func selectLogo(url: String) {
        guard item.modelContext != nil else { return }
        guard url != item.effectiveLogoURL else { return }

        item.customLogoURL = url
        item.commitChange(dirty: [.badge])
        AppErrorState.shared.showToast("Logo updated", style: .success)
    }

    func resetToDefaultLogo() {
        guard item.modelContext != nil, item.customLogoURL != nil else { return }

        item.customLogoURL = nil
        item.commitChange(dirty: [.badge])
        AppErrorState.shared.showToast("Logo reset to default", style: .success)
    }

    private func fetchWatchProvidersIfNeeded() {
        guard watchProviders.isEmpty else { return }
        guard let tmdbIDString = item.id.split(separator: "_").last, let tmdbID = Int(tmdbIDString) else { return }
        let type = item.type ?? .movie
        watchProvidersTask?.cancel()
        watchProvidersTask = Task {
            let providers = await APIClient.shared.fetchWatchProviders(tmdbID: tmdbID, type: type)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.watchProviders = providers
                let names = providers.map(\.name)
                if self.item.cachedWatchProviders != names {
                    self.item.cachedWatchProviders = names
                    self.item.commitChange(dirty: [.badge, .metadata])
                }
            }
        }
    }

    func fetchRecommendations() {
        recsTask?.cancel()
        guard MooreMetricsService.shared.isConfigured else { return }
        guard !item.title.isEmpty else { return }
        guard recommendations.isEmpty else { return }

        let title = item.title
        let domain = MooreMetricsService.recommendedDomain(for: item)
        let cacheKey = "\(domain)_\(title)"

        isLoadingRecommendations = true

        recsTask = Task { [weak self] in
            let results = await RecommendationService.fetchRecommendations(
                titles: [title],
                domain: domain,
                cachePrefix: "mm_rec_cache_detail_",
                cacheKey: cacheKey
            )
            guard !Task.isCancelled else { return }

            if results.isEmpty {
                AppErrorState.shared.showToast("No recommendations found", style: .info)
            }

            await MainActor.run { [weak self] in
                self?.recommendations = results
                self?.isLoadingRecommendations = false
            }
        }
    }

    func markAllAsWatched() {
        guard item.modelContext != nil else { return }

        if item.type == .tvShow {
            item.markLoadedEpisodesAsWatched()
            if let container = item.modelContext?.container {
                let rawID = item.id
                Task.detached(priority: .userInitiated) {
                    let svc = BackgroundDataService(modelContainer: container)
                    await svc.markAllEpisodesAsWatched(itemID: rawID)
                }
            }
        }

        if item.state != .completed {
            item.stateValue = MediaState.completed.rawValue
            item.lastInteractionDate = Date()
            item.lastStateChangeDate = Date()
            item.syncCachedProperties(dirty: [.progress, .badge])
        }
        if let context = item.modelContext {
            SaveCoordinator.shared.requestSave(context)
        }
        MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
    }

    func fetchEpisodes(for season: TVSeason, force: Bool = false) {
        guard item.modelContext != nil else { return }
        let seasonID = season.persistentModelID
        
        isRefreshing = true
        Task { [weak self] in
            await self?.fetchEpisodesIfNeeded(for: seasonID, markAsWatched: false, force: force)
            await MainActor.run { [weak self] in
                self?.isRefreshing = false
            }
        }
    }
    
    private func fetchEpisodesIfNeeded(for seasonID: PersistentIdentifier, markAsWatched: Bool, force: Bool = false) async {
        guard let tv = self.item.tvShowDetails,
              let season = tv.seasons.first(where: { $0.persistentModelID == seasonID }) else { return }
        
        if !force {
            if season.episodeCount > 0 && season.episodes.count >= season.episodeCount { return }
        }
        
        let tmdbID = tv.tmdbID
        let seasonNumber = season.seasonNumber
        let syncKey = "fetch_episodes_\(tmdbID)_\(seasonNumber)"
        
        do {
            try await SyncCoordinator.shared.perform(key: syncKey) {
                let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: seasonNumber, force: force)
                
                await MainActor.run {
                    guard self.item.modelContext != nil, !self.item.isDeleted else { return }
                    // Re-fetch season in MainActor context
                    guard let currentSeason = self.item.tvShowDetails?.seasons
                        .first(where: { !$0.isDeleted && $0.modelContext != nil && $0.persistentModelID == seasonID }) else { return }
                    
                    let showIDInt = tmdbID
                    let seasonNum = seasonNumber
                    let batchDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.showID == showIDInt })
                    let existingEpisodes = (try? self.item.modelContext?.fetch(batchDescriptor)) ?? []
                    var existingMap: [String: TVEpisode] = [:]
                    for ep in existingEpisodes {
                        if let uid = ep.uniqueID {
                            existingMap[uid] = ep
                        }
                    }
                    
                    for ep in episodes {
                        let epUniqueID = "\(tmdbID)_\(seasonNum)_\(ep.episodeNumber)"
                        let episode = existingMap[epUniqueID] ?? TVEpisode(
                            episodeNumber: ep.episodeNumber,
                            seasonNumber: seasonNumber,
                            name: ep.name ?? "Episode \(ep.episodeNumber)",
                            overview: ep.overview ?? "",
                            airDate: ep.airDate,
                            airstamp: nil,
                            runtime: ep.runtime,
                            showID: tmdbID
                        )
                        
                        if episode.modelContext == nil {
                            episode.season = currentSeason
                            self.item.modelContext?.insert(episode)
                        } else if episode.season?.persistentModelID != currentSeason.persistentModelID {
                            episode.season = currentSeason
                        }
                        
                        episode.markWatched(markAsWatched)
                    }
                    
                    self.item.tvShowDetails?.recalculateCachedProperties(triggerSync: true, force: true)
                    self.item.syncCachedProperties(dirty: [.progress, .badge])
                    if currentSeason.episodeCount < episodes.count {
                        currentSeason.episodeCount = episodes.count
                    }
                }
            }
        } catch {
            await MainActor.run {
                AppErrorState.shared.surfaceError("Failed to fetch episodes: \(error.localizedDescription)")
            }
        }
    }
    
    private var recsTask: Task<Void, Never>?
    private var logoTask: Task<Void, Never>?
    private var posterTask: Task<Void, Never>?
    private var watchProvidersTask: Task<Void, Never>?
    private var episodesTask: Task<Void, Never>?

    func cancelTasks() {
        recsTask?.cancel()
        logoTask?.cancel()
        posterTask?.cancel()
        watchProvidersTask?.cancel()
        episodesTask?.cancel()
    }

    func markNextEpisodeWatched() {
        guard item.modelContext != nil, let tv = item.tvShowDetails else { return }
        
        // Optimize: Make sure seasons are loaded
        let sortedSeasons = tv.seasons.sorted { $0.seasonNumber < $1.seasonNumber }
        guard let currentSeason = sortedSeasons.first(where: { $0.watchedEpisodesCount < $0.totalEpisodesCount }) else { return }
        
        // Make sure episodes are loaded or fetched
        if currentSeason.episodes.isEmpty {
            fetchEpisodes(for: currentSeason)
            return
        }
        
        let sortedEpisodes = currentSeason.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
        if let next = sortedEpisodes.first(where: { !$0.isWatched }) {
            next.markWatched(true)
            item.lastInteractionDate = Date()
            item.syncCachedProperties(dirty: [.progress, .badge])
            if let context = item.modelContext {
                SaveCoordinator.shared.requestSave(context)
            }
            MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
        }
    }

    func toggleWatched() {
        guard item.modelContext != nil else { return }
        if item.state == .completed {
            item.state = .wishlist
        } else {
            item.state = .completed
        }
        item.lastInteractionDate = Date()
        item.syncCachedProperties(dirty: [.progress, .badge])
        if let context = item.modelContext {
            SaveCoordinator.shared.requestSave(context)
        }
        MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
    }

    func cycleStatus() {
        guard item.modelContext != nil else { return }
        let allStates = MediaItem.availableStates(for: item.type ?? .movie, progress: item.storedProgress)
        guard !allStates.isEmpty else { return }
        
        let currentIndex = allStates.firstIndex(of: item.state ?? .wishlist) ?? 0
        let nextIndex = (currentIndex + 1) % allStates.count
        let nextState = allStates[nextIndex]
        
        withAnimation(AppTheme.Animation.springSnappy) {
            item.state = nextState
            item.lastUpdated = Date()
            item.lastInteractionDate = Date()
            item.syncCachedProperties(dirty: [.badge, .searchable])
        }
        if let context = item.modelContext {
            SaveCoordinator.shared.requestSave(context)
        }
        MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
    }
}
