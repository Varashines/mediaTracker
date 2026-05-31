import SwiftUI
import SwiftData

@Observable @MainActor
class DetailViewModel {
    var item: MediaItem
    var isRefreshing = false
    var themeColor: Color = Color.secondary.opacity(0.1)
    var secondaryThemeColor: Color = Color.secondary.opacity(0.06)
    
    // Phase 5 Performance: Cache scheme-aware colors to avoid per-frame math in MeshGradient
    var vibrantThemeColor: Color = .clear
    var contrastThemeColor: Color = .clear
    var warmThemeColor: Color = .clear
    var coolThemeColor: Color = .clear
    var secondaryVibrantThemeColor: Color = .clear
    var secondaryWarmThemeColor: Color = .clear
    var secondaryCoolThemeColor: Color = .clear
    var recommendations: [MooreMetricsRecommendation] = []
    var isLoadingRecommendations = false
    var debugSelectedTraits: [String] = []
    
    init(item: MediaItem) {
        self.item = item
        // Initial pre-warm for cached data removed to speed up transitions.
        // Will be triggered lazily if needed.
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
        guard let context = item.modelContext, !SleepManager.shared.isAsleep else { return }

        // Priority 1: Pre-calculated Poster Color from SwiftData
        if let hex = item.themeColorHex {
            if hex.contains("|") {
                let parts = hex.split(separator: "|", maxSplits: 1).map(String.init)
                if parts.count == 2, let primary = Color(hex: parts[0]), let secondary = Color(hex: parts[1]) {
                    self.themeColor = primary
                    self.secondaryThemeColor = secondary
                    self.recalculateVibrantPalette()
                    return
                }
            } else if let cachedColor = Color(hex: hex) {
                self.themeColor = cachedColor
                self.recalculateVibrantPalette()
                return
            }
        }

        // Priority 2: Network/Studio Theme Color (backup)
        if let networkName = item.cachedNetwork {
            let first = networkName.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? networkName
            let descriptor = FetchDescriptor<NetworkEntity>(predicate: #Predicate<NetworkEntity> { $0.name == first })
            if let network = try? context.fetch(descriptor).first, let hex = network.themeColorHex, let netColor = Color(hex: hex) {
                self.themeColor = netColor
                self.secondaryThemeColor = netColor
                self.recalculateVibrantPalette()
                return
            }
        }

        // Priority 3: Neutral fallback (never use global accent)
        self.themeColor = Color.secondary.opacity(0.15)
        self.secondaryThemeColor = Color.secondary.opacity(0.1)
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
        self.contrastThemeColor = themeColor.highContrastAccent(colorScheme: scheme)
        self.warmThemeColor = vibrantThemeColor.hueShift(by: 0.05)
        self.coolThemeColor = vibrantThemeColor.hueShift(by: -0.05)
        
        // Secondary color palette for 2-tone ambient background
        self.secondaryVibrantThemeColor = secondaryThemeColor.luminousAccent(colorScheme: scheme)
        self.secondaryWarmThemeColor = secondaryVibrantThemeColor.hueShift(by: 0.05)
        self.secondaryCoolThemeColor = secondaryVibrantThemeColor.hueShift(by: -0.05)
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

        let hasData = item.lastUpdated != nil

        if !force && DataService.shared.hasRefreshedThisSession(id: item.id) {
            return
        }

        if !force && hasData && !needsUpdate && !needsOMDBData { return }
        
        guard let context = item.modelContext else { return }

        isRefreshing = true
        let rawID = item.id
        let startTime = ContinuousClock.now

        Task { [weak self] in
            let backgroundService = BackgroundDataService(modelContainer: context.container)
            let success = await backgroundService.refreshSingleItem(id: rawID, force: force)

            let elapsed = startTime.duration(to: .now)
            let minDuration: Duration = .milliseconds(400)
            if elapsed < minDuration {
                try? await Task.sleep(for: minDuration - elapsed)
            }

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
        item.syncCachedProperties()
        item.tvShowDetails?.recalculateCachedProperties()

        updateThemeColor()
    }

    func fetchRecommendations() {
        recsTask?.cancel()
        guard MooreMetricsService.shared.isConfigured else { return }
        guard !item.title.isEmpty else { return }
        guard recommendations.isEmpty else { return }

        let title = item.title
        let domain = MooreMetricsService.recommendedDomain(for: item)
        let cacheKey = "\(domain)_\(title)"

        // Check 30-day persisted cache
        if let cached = loadCachedRecs(key: cacheKey), !cached.isEmpty {
            recommendations = cached
            return
        }

        isLoadingRecommendations = true

        recsTask = Task { [weak self] in
            async let asyncLabels = MooreMetricsService.shared.fetchCharacteristics(for: domain)
            var mutableResults = await MooreMetricsService.shared.recommend(domain: domain, items: [title], limit: 10, labels: await asyncLabels)
            guard !mutableResults.isEmpty else {
                await MainActor.run {
                    AppErrorState.shared.showToast("No recommendations found", style: .info)
                    self?.isLoadingRecommendations = false
                }
                return
            }
            guard !Task.isCancelled else { return }

            if mutableResults.count >= 3 {
                let topProfile = MooreMetricsService.shared.buildPreferenceProfile(
                    from: mutableResults.map { ($0.characteristics, $0.score) }
                )
                if !topProfile.isEmpty {
                    let debugMode = UserDefaults.standard.bool(forKey: UserDefaultsKeys.mmDebugMode.rawValue)
                    if debugMode {
                        await MainActor.run { [weak self] in
                            self?.debugSelectedTraits = Array(topProfile.keys)
                        }
                    }

                    guard !Task.isCancelled else { return }

                    let prefResults = await MooreMetricsService.shared.recommendByPreferences(
                        domain: domain, preferences: topProfile, limit: 5, labels: await asyncLabels
                    )
                    var seen = Set(mutableResults.map(\.name))
                    for rec in prefResults where !seen.contains(rec.name) {
                        mutableResults.append(rec)
                        seen.insert(rec.name)
                    }
                }
            }

            let finalResults = Array(mutableResults.prefix(10))
            self?.saveCachedRecs(key: cacheKey, recommendations: finalResults)

            await MainActor.run { [weak self] in
                guard !Task.isCancelled else { return }
                self?.recommendations = finalResults
                self?.isLoadingRecommendations = false
            }
        }
    }

    private func saveCachedRecs(key: String, recommendations: [MooreMetricsRecommendation]) {
        let prefix = "mm_rec_cache_detail_"
        if let data = try? JSONEncoder().encode(recommendations) {
            UserDefaults.standard.set(data, forKey: prefix + key)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: prefix + key + "_ts")
        }
    }

    private func loadCachedRecs(key: String) -> [MooreMetricsRecommendation]? {
        let prefix = "mm_rec_cache_detail_"
        let thirtyDays: TimeInterval = 30 * 24 * 3600

        guard let data = UserDefaults.standard.data(forKey: prefix + key),
              let cached = try? JSONDecoder().decode([MooreMetricsRecommendation].self, from: data),
              let timestamp = UserDefaults.standard.object(forKey: prefix + key + "_ts") as? TimeInterval,
              Date().timeIntervalSince1970 - timestamp < thirtyDays else {
            return nil
        }
        return cached
    }

    func markAllAsWatched() {
        guard item.modelContext != nil else { return }
        if item.state != .completed {
            item.state = .completed
        }
        if let context = item.modelContext {
            SaveCoordinator.shared.requestSave(context)
        }
        MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
    }

    func fetchEpisodes(for season: TVSeason) {
        guard item.modelContext != nil else { return }
        let seasonID = season.persistentModelID
        
        isRefreshing = true
        Task { [weak self] in
            await self?.fetchEpisodesIfNeeded(for: seasonID, markAsWatched: false)
            await MainActor.run { [weak self] in
                self?.isRefreshing = false
            }
        }
    }
    
    private func fetchEpisodesIfNeeded(for seasonID: PersistentIdentifier, markAsWatched: Bool) async {
        guard let tv = self.item.tvShowDetails,
              let season = tv.seasons.first(where: { $0.persistentModelID == seasonID }) else { return }
        
        // Phase 5: Resiliency Check - Skip fetching if the season brief says there are no episodes
        if season.episodeCount == 0 { return }
        
        // Skip if already has episodes and not forcing
        if season.totalEpisodesCount > 0 { return }
        
        let tmdbID = tv.tmdbID
        let seasonNumber = season.seasonNumber
        let syncKey = "fetch_episodes_\(tmdbID)_\(seasonNumber)"
        
        do {
            try await SyncCoordinator.shared.perform(key: syncKey) {
                let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: seasonNumber)
                
                await MainActor.run {
                    guard self.item.modelContext != nil, !self.item.isDeleted else { return }
                    // Re-fetch season in MainActor context
                    guard let currentSeason = self.item.tvShowDetails?.seasons
                        .first(where: { !$0.isDeleted && $0.modelContext != nil && $0.persistentModelID == seasonID }) else { return }
                    
                    for ep in episodes {
                        let epUniqueID = "\(tmdbID)_\(seasonNumber)_\(ep.episodeNumber)"
                        
                        // Robust deduplication check: Check both the persistent store and the current season's relationship
                        let eDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.uniqueID == epUniqueID })
                        let existingEpisode = try? self.item.modelContext?.fetch(eDescriptor).first
                        
                        let episode = existingEpisode ?? TVEpisode(
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
                        
                        // Ensure it's in the season's episodes array if not already (for relationship integrity)
                        if !currentSeason.episodes.contains(where: { $0.uniqueID == epUniqueID }) {
                            currentSeason.episodes.append(episode)
                        }
                        
                        episode.markWatched(markAsWatched)
                    }
                    
                    self.item.tvShowDetails?.recalculateCachedProperties(triggerSync: true, force: true)
                    self.item.syncCachedProperties()
                }
            }
        } catch {
            await MainActor.run {
                AppErrorState.shared.surfaceError("Failed to fetch episodes: \(error.localizedDescription)")
            }
        }
    }
    
    private var recsTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    func checkOverallCompletion() {
        guard item.modelContext != nil else { return }
        
        // 1. Instant Optimistic UI Update
        withAnimation {
            item.syncCachedProperties()
            item.lastStateChangeDate = Date() // Trigger grid refresh
            item.lastInteractionDate = Date() // Bump to top of Continue Watching
            
            // Broadcast the change so the Main Page also updates its badge immediately
            if let posterURL = item.posterURL {
                ImageCache.shared.ping(url: posterURL)
            }
        }
        
        // 2. Debounce the heavy database sync and global broadcast
        saveTask?.cancel()
        let itemID = item.persistentModelID
        let container = item.modelContext?.container
        
        saveTask = Task { @MainActor [weak self] in
            // Wait 0.5s to see if the user taps another episode
            try? await Task.sleep(nanoseconds: 500_000_000)
            if Task.isCancelled { return }
            
            guard let self = self, self.item.modelContext != nil else { return }
            
            self.item.tvShowDetails?.recalculateCachedProperties(force: true)
            self.item.syncCachedProperties()
            
            if let context = self.item.modelContext {
                SaveCoordinator.shared.requestSave(context)
            }
            
            Task.detached {
                if let container = container {
                    let sync = DiscoverySyncService(modelContainer: container)
                    await sync.updateItemAdded(itemID)
                }
            }
            
 
        }
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
            item.syncCachedProperties()
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
        item.syncCachedProperties()
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
        
        withAnimation {
            item.state = nextState
            item.lastUpdated = Date()
            item.lastInteractionDate = Date()
            item.syncCachedProperties()
            if let context = item.modelContext {
                SaveCoordinator.shared.requestSave(context)
            }
            MediaStateService.shared.postMediaStateChanged(itemID: item.persistentModelID)
        }
    }
}
