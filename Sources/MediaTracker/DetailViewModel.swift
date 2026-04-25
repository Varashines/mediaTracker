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
        
        // Immediate local cleanup of legacy crew cards (non-blocking)
        Task {
            guard let context = item.modelContext else { return }
            await MainActor.run {
                if let tv = item.tvShowDetails {
                    for member in tv.cast {
                        if member.characterName == "Creator" || member.characterName == "Director" {
                            context.delete(member)
                        }
                    }
                }
                if let movie = item.movieDetails {
                    for member in movie.cast {
                        if member.characterName == "Creator" || member.characterName == "Director" {
                            context.delete(member)
                        }
                    }
                }
                try? context.save()
            }
        }
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
        // Skip if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        if let hex = item.themeColorHex, let cachedColor = Color(hex: hex) {
            self.themeColor = cachedColor
            return
        }
        
        // Extraction logic
        if let posterURL = item.posterURL, let url = URL(string: posterURL) {
            Task {
                // Try to get from cache first
                if let container = await ImageCache.shared.get(forKey: url.absoluteString, targetSize: CGSize(width: 320, height: 480)) {
                    let extracted = ColorExtractor.dominantColor(from: container.image)
                    let hex = extracted.toHex()
                    
                    await MainActor.run {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            self.themeColor = extracted
                            self.item.themeColorHex = hex
                            // No need to explicitly save, SwiftData handles it or it will be saved on refresh
                        }
                    }
                    return
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
        // Skip if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        let hasData = item.movieDetails != nil || (item.type == .tvShow && (item.tvShowDetails != nil && item.tvShowDetails?.status != nil))
        
        // Session Throttling
        if !force && DataService.shared.hasRefreshedThisSession(id: item.id) {
            return
        }

        if !force && hasData && !needsUpdate { return }
        
        // Capture context while on MainActor
        guard let context = item.modelContext else { return }
        
        isRefreshing = true
        let itemID = item.persistentModelID
        let rawID = item.id
        
        Task {
            let backgroundService = BackgroundDataService(modelContainer: context.container)
            let success = await backgroundService.refreshSingleItem(id: itemID)
            
            await MainActor.run {
                if success {
                    DataService.shared.markAsRefreshedThisSession(id: rawID)
                    updateThemeColor()
                    self.prewarmCast()
                }
                self.isRefreshing = false
            }
        }
    }

    private func prewarmCast() {
        let cast = (item.movieDetails?.cast ?? item.tvShowDetails?.cast) ?? []
        let urls = cast.prefix(6).compactMap { $0.profileURL }.compactMap { URL(string: $0) }
        if !urls.isEmpty {
            ImageCache.shared.prewarmImages(urls: urls, targetSize: CGSize(width: 120, height: 180), priority: .low)
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
                        self.item.lastInteractionDate = Date()
                        tv.recalculateCachedProperties()
                        self.item.updateSearchableText()
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
                    self.item.tvShowDetails?.recalculateCachedProperties()
                    self.item.updateSearchableText()
                    self.checkOverallCompletion()
                }
            } catch {
                print("❌ Error fetching episodes in markAllAsWatched: \(error)")
            }
        }
    }
    
    func checkOverallCompletion() {
        withAnimation {
            item.checkOverallCompletion()
            item.tvShowDetails?.recalculateCachedProperties() // Fallback to ensure counts are fresh
            item.syncCachedProperties() // Explicitly fix denormalization gap
            item.lastStateChangeDate = Date() // Trigger grid refresh
            
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
