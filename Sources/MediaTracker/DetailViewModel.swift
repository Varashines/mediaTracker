import SwiftUI
import SwiftData

@Observable @MainActor
class DetailViewModel {
    var item: MediaItem
    var isRefreshing = false
    var themeColor: Color = Color.secondary.opacity(0.1)
    
    init(item: MediaItem) {
        self.item = item
        // Initial pre-warm for cached data
        prewarmCast()
    }
    
    var needsUpdate: Bool {
        guard let lastUpdated = item.lastUpdated else { return true }
        
        // Active TV shows should check for updates every 24 hours
        if item.type == .tvShow && item.state == .active {
            return Date().timeIntervalSince(lastUpdated) > 86400
        }
        
        // Maintenance rule for TV shows (30 days)
        if item.type == .tvShow {
            return item.requiresMaintenanceRefresh
        }
        
        // Default 24h for movies
        return Date().timeIntervalSince(lastUpdated) > 86400
    }
    
    func updateThemeColor() {
        // Skip if item is deleted or app is in sleep mode
        guard item.modelContext != nil, !item.isDeleted, !SleepManager.shared.isAsleep else { return }

        if let hex = item.themeColorHex, let cachedColor = Color(hex: hex) {
            self.themeColor = cachedColor
            return
        }
        
        // Extraction logic
        if let posterURL = item.posterURL, let url = URL(string: posterURL) {
            Task { [weak self] in
                // Try to get from cache first
                if let container = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: .thumbMedium) {
                    let extracted = await ColorExtractor.dominantColor(from: container.image)
                    let hex = extracted.toHex()
                    
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.themeColor = extracted
                            self.item.themeColorHex = hex
                        }
                    }
                }
            }
        }
        
        // Read current accent from storage for fallback
        let appAccentRaw = UserDefaults.standard.string(forKey: "app_accent") ?? AppAccent.cosmic.rawValue
        let appAccent = AppAccent(rawValue: appAccentRaw) ?? .cosmic
        
        withAnimation {
            self.themeColor = appAccent.color
        }
    }
    
    func refreshData(force: Bool = false) {
        // Skip if item is deleted or app is in sleep mode
        guard item.modelContext != nil, !item.isDeleted, !SleepManager.shared.isAsleep else { return }

        let hasData = item.movieDetails != nil || (item.type == .tvShow && (item.tvShowDetails != nil && item.tvShowDetails?.status != nil))
        
        // Session Throttling
        if !force && DataService.shared.hasRefreshedThisSession(id: item.id) {
            return
        }

        if !force && hasData && !needsUpdate { return }
        
        // Capture context while on MainActor
        guard let context = item.modelContext else { return }

        isRefreshing = true
        let rawID = item.id

        Task { [weak self] in
            let backgroundService = BackgroundDataService(modelContainer: context.container)
            let success = await backgroundService.refreshSingleItem(id: rawID, force: force)

            await MainActor.run { [weak self] in
                guard let self = self, self.item.modelContext != nil, !self.item.isDeleted else { return }
                if success {
                    self.refreshLocalItem()
                }
                self.isRefreshing = false
            }
        }
    }

    func refreshLocalItem() {
        guard !item.isDeleted else { return }
        
        // SwiftData automatically propagates background saves to the main context.
        // FORCE RELOAD: Access the collections to trigger a merge of background data.
        if let tv = item.tvShowDetails {
            _ = tv.seasons.count
            _ = tv.cast.count // Force cast merge
            for s in tv.seasons {
                _ = s.episodes.count
            }
        }
        
        if let movie = item.movieDetails {
            _ = movie.cast.count // Force cast merge
        }

        item.syncCachedProperties()
        item.tvShowDetails?.recalculateCachedProperties()
        
        updateThemeColor()
        self.prewarmCast()
    }

    private func prewarmCast() {
        guard item.modelContext != nil, !item.isDeleted else { return }
        let cast = (item.movieDetails?.cast ?? item.tvShowDetails?.cast) ?? []
        let urls = cast.prefix(6).compactMap { $0.profileURL }.compactMap { URL(string: $0) }
        if !urls.isEmpty {
            ImageCache.shared.prewarmImages(urls: urls, targetSize: CGSize(width: 120, height: 180), priority: .low)
        }
    }
    
    func markAllAsWatched() {
        guard item.modelContext != nil, !item.isDeleted else { return }
        if let tv = item.tvShowDetails {
            // Instant UI Update: Mark all CURRENTLY LOADED episodes as watched on MainActor
            for season in tv.seasons {
                for episode in season.episodes {
                    episode.isWatched = true
                }
            }
            
            // Heal/Sync check before batch marking
            let tmdbIDString = item.id.split(separator: "_").last ?? item.id[...]
            guard Int(tmdbIDString) != nil else { return }
            
            let seasonIDs = tv.seasons.map { $0.persistentModelID }
            let itemID = item.id
            let container = item.modelContext?.container
            
            isRefreshing = true // Show loading state during batch update
            
            Task { [weak self] in
                guard let self = self else { return }
                
                // Concurrent fetching of missing episodes and re-linking
                await withTaskGroup(of: Void.self) { group in
                    for seasonID in seasonIDs {
                        group.addTask {
                            await self.fetchEpisodesIfNeeded(for: seasonID, markAsWatched: true)
                        }
                    }
                }
                
                // Perform batch update on background actor (handles orphaned/unloaded episodes)
                if let container = container {
                    let backgroundService = BackgroundDataService(modelContainer: container)
                    await backgroundService.markAllEpisodesAsWatched(itemID: itemID)
                }
                
                await MainActor.run { [weak self] in
                    guard let self = self, self.item.modelContext != nil, !self.item.isDeleted else { return }
                    self.refreshLocalItem()
                    self.isRefreshing = false
                }
            }
        }
    }

    func fetchEpisodes(for season: TVSeason) {
        guard item.modelContext != nil, !item.isDeleted else { return }
        let seasonID = season.persistentModelID
        
        Task { [weak self] in
            await self?.fetchEpisodesIfNeeded(for: seasonID, markAsWatched: false)
        }
    }
    
    private func fetchEpisodesIfNeeded(for seasonID: PersistentIdentifier, markAsWatched: Bool) async {
        guard let tv = self.item.tvShowDetails,
              let season = tv.seasons.first(where: { $0.persistentModelID == seasonID }) else { return }
        
        // Skip if already has episodes and not forcing
        if !season.episodes.isEmpty { return }
        
        let tmdbID = tv.tmdbID
        let seasonNumber = season.seasonNumber
        let syncKey = "fetch_episodes_\(tmdbID)_\(seasonNumber)"
        
        do {
            try await SyncCoordinator.shared.perform(key: syncKey) {
                let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: seasonNumber)
                
                await MainActor.run {
                    guard self.item.modelContext != nil, !self.item.isDeleted else { return }
                    // Re-fetch season in MainActor context
                    guard let currentSeason = self.item.tvShowDetails?.seasons.first(where: { $0.persistentModelID == seasonID }) else { return }
                    
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
                        
                        episode.isWatched = markAsWatched
                    }
                    
                    self.item.tvShowDetails?.recalculateCachedProperties()
                    self.item.updateSearchableText()
                    self.checkOverallCompletion()
                }
            }
        } catch {
            print("❌ Error fetching episodes: \(error)")
        }
    }
    
    func checkOverallCompletion() {
        guard item.modelContext != nil, !item.isDeleted else { return }
        withAnimation {
            item.checkOverallCompletion()
            item.tvShowDetails?.recalculateCachedProperties() // Fallback to ensure counts are fresh
            item.syncCachedProperties() // Explicitly fix denormalization gap
            item.lastStateChangeDate = Date() // Trigger grid refresh
            item.lastInteractionDate = Date() // Bump to top of Continue Watching

            // EXPLICIT SAVE: Ensure all background actors see the latest state before the notification is sent.
            try? item.modelContext?.save()            
            // Sync Discovery Entities
            let itemID = item.persistentModelID
            let container = item.modelContext?.container
            Task.detached {
                if let container = container {
                    let sync = DiscoverySyncService(modelContainer: container)
                    let actorContext = ModelContext(container)
                    if let fetchedItem = actorContext.model(for: itemID) as? MediaItem {
                        await sync.updateItemAdded(fetchedItem)
                    }
                }
            }
            
            // Phase 1: Global Pulse
            NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
            
            // Broadcast the change so the Main Page also updates its badge
            if let posterURL = item.posterURL {
                ImageCache.shared.ping(url: posterURL)
            }
        }
    }
}
