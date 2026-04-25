import Foundation
import SwiftData
import SwiftUI

struct LibraryBackup: Codable {
    let items: [MediaItemData]
    var version: Int = 1
}

struct MediaItemData: Codable {
    let id: String
    let title: String
    let type: String
    let state: String
    let dateAdded: Date
    let taste: String?
}

@ModelActor
actor MaintenanceService {
    func performLibraryHeal() async {
        let descriptor = FetchDescriptor<MediaItem>()
        let items = (try? modelContext.fetch(descriptor)) ?? []
        
        for item in items {
            // 1. Assign uniqueIDs to legacy data
            if let tmdbID = Int(item.id) {
                if let tv = item.tvShowDetails {
                    tv.item = item
                    for season in tv.seasons {
                        if season.uniqueID == nil {
                            season.uniqueID = "\(tmdbID)_\(season.seasonNumber)"
                        }
                        season.tvShowDetails = tv
                        
                        for episode in season.episodes {
                            if episode.uniqueID == nil {
                                episode.uniqueID = "\(tmdbID)_\(season.seasonNumber)_\(episode.episodeNumber)"
                            }
                            episode.season = season
                        }
                        
                        // 2. Remove duplicate episodes within the same season
                        let grouped = Dictionary(grouping: season.episodes, by: { $0.episodeNumber })
                        for (_, eps) in grouped where eps.count > 1 {
                            // Keep the one with the most data
                            let sorted = eps.sorted { ($0.airDate ?? "").count > ($1.airDate ?? "").count }
                            for i in 1..<sorted.count {
                                modelContext.delete(sorted[i])
                            }
                        }
                    }
                    
                    // 3. Purge legacy Crew cards
                    for member in tv.cast {
                        if member.characterName == "Creator" || member.characterName == "Director" {
                            modelContext.delete(member)
                        }
                    }
                    
                    tv.recalculateCachedProperties(triggerSync: true)
                }
                
                if let movie = item.movieDetails {
                    for member in movie.cast {
                        if member.characterName == "Creator" || member.characterName == "Director" {
                            modelContext.delete(member)
                        }
                    }
                }
            }
            item.updateSearchableText()
        }
        
        try? modelContext.save()
        print("✅ Maintenance: Library heal complete.")
    }
}

@MainActor
class DataService {
    static let shared = DataService()
    
    /// Tracks items refreshed during this app session to avoid redundant network calls.
    private var sessionRefreshedItems = Set<String>()
    
    // Feedback State
    var isRunningMaintenance = false
    var showMaintenanceComplete = false

    func hasRefreshedThisSession(id: String) -> Bool {
        return sessionRefreshedItems.contains(id)
    }
    
    func markAsRefreshedThisSession(id: String) {
        sessionRefreshedItems.insert(id)
    }

    func refreshMetadata(for items: [MediaItem], modelContext: ModelContext, metadataOnly: Bool = false) {
        // Skip if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        let itemIDs = items.map { $0.persistentModelID }
        let backgroundService = BackgroundDataService(modelContainer: modelContext.container)
        
        Task {
            await backgroundService.refreshMetadata(for: itemIDs, metadataOnly: metadataOnly)
        }
    }

    func runMaintenance(modelContext: ModelContext) {
        guard !isRunningMaintenance else { return }
        isRunningMaintenance = true
        
        let service = MaintenanceService(modelContainer: modelContext.container)
        Task {
            await service.performLibraryHeal()
            await MainActor.run {
                self.isRunningMaintenance = false
                self.showMaintenanceComplete = true
            }
        }
    }

    func exportLibrary(items: [MediaItem]) {
        let exportItems = items.map { item in
            MediaItemData(
                id: item.id,
                title: item.title,
                type: item.type?.rawValue ?? "Movie",
                state: item.state?.rawValue ?? "Wishlist",
                dateAdded: item.dateAdded,
                taste: item.tasteValue
            )
        }
        
        let backup = LibraryBackup(items: exportItems)
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MediaTracker_Backup_\(Date().formatted(date: .abbreviated, time: .omitted)).json"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(backup)
                    try data.write(to: url)
                    print("✅ Library exported to \(url.path)")
                } catch {
                    print("❌ Export error: \(error)")
                }
            }
        }
    }

    func importLibrary(modelContext: ModelContext) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let backup = try JSONDecoder().decode(LibraryBackup.self, from: data)
                    
                    // Pre-fetch existing to avoid duplicates
                    let descriptor = FetchDescriptor<MediaItem>()
                    let existing = (try? modelContext.fetch(descriptor)) ?? []
                    let existingKeys = Set(existing.map { "\($0.id)_\($0.type?.rawValue ?? "")" })
                    
                    for itemData in backup.items {
                        let key = "\(itemData.id)_\(itemData.type)"
                        if !existingKeys.contains(key) {
                            let item = MediaItem(
                                id: itemData.id,
                                title: itemData.title,
                                overview: "",
                                posterURL: nil,
                                releaseDate: nil,
                                type: MediaType(rawValue: itemData.type) ?? .movie
                            )
                            item.state = MediaState(rawValue: itemData.state) ?? .wishlist
                            item.dateAdded = itemData.dateAdded
                            item.tasteValue = itemData.taste ?? "None"
                            modelContext.insert(item)
                            }                    }
                    try? modelContext.save()
                    print("✅ Library imported successfully.")
                } catch {
                    print("❌ Import error: \(error)")
                }
            }
        }
    }
}

/// Handles high-priority background actions like those triggered by notifications.
@ModelActor
actor BackgroundActionService {
    func markAsWatched(itemID: String, type: String, season: Int? = nil, episode: Int? = nil) throws {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate<MediaItem> { $0.id == itemID })
        guard let item = try modelContext.fetch(descriptor).first else { return }
        
        if type == "movie" {
            item.state = .completed
            item.lastStateChangeDate = Date()
            item.lastInteractionDate = Date()
        } else if type == "tvShow", let s = season, let e = episode {
            // Find specific episode
            if let tvDetails = item.tvShowDetails {
                for seasonObj in tvDetails.seasons where seasonObj.seasonNumber == s {
                    for episodeObj in seasonObj.episodes where episodeObj.episodeNumber == e {
                        episodeObj.isWatched = true
                        item.lastInteractionDate = Date()
                        break
                    }
                }
            }
        }
        
        item.syncCachedProperties()
        item.updateSearchableText()
        try modelContext.save()
        
        // Notify UI
        Task { @MainActor in
            NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
        }
    }
}

/// A background actor for heavy SwiftData operations and throttled networking.
@ModelActor
actor BackgroundDataService {
    private let decoder = JSONDecoder()

    private var isThermalThrottled: Bool {
        // Phase 1 Optimization: Thermal Awareness for fanless M1 Air
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical {
            return true
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return true
        }
        return false
    }

    func refreshMetadata(for itemIDs: [PersistentIdentifier], metadataOnly: Bool = false) async {
        if isThermalThrottled {
            print("🌡️ Thermal state serious or Low Power Mode active. Skipping background refresh.")
            return
        }
        
        var errorCount = 0
        
        // Phase 2 Optimization: CPU-Aware Throttling
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let maxConcurrent = max(2, min(5, processorCount / 2))
        
        // Use withTaskGroup to throttle network requests
        await withTaskGroup(of: Bool.self) { group in
            var activeTasks = 0
            
            for id in itemIDs {
                if activeTasks >= maxConcurrent {
                    if await !group.next()! { errorCount += 1 }
                    activeTasks -= 1
                }
                
                group.addTask {
                    await self.refreshSingleItem(id: id, metadataOnly: metadataOnly)
                }
                activeTasks += 1
            }
            
            while activeTasks > 0 {
                if await !group.next()! { errorCount += 1 }
                activeTasks -= 1
            }
        }
        
        print("✅ Background Refresh: Completed with \(errorCount) errors.")
    }

    func refreshSingleItem(id: PersistentIdentifier, metadataOnly: Bool = false) async -> Bool {
        guard let item = modelContext.model(for: id) as? MediaItem else { return false }
        
        do {
            if item.type == .movie, let tmdbID = Int(item.id) {
                let details = try await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                
                // Diff-based update
                item.releaseDate = DateUtils.parseDate(details.releaseDate)
                
                // Poster & Backdrop Upgrade
                if let poster = details.posterPath {
                    item.posterURL = "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(poster)"
                }
                if let backdrop = details.backdropPath {
                    item.backdropURL = "https://image.tmdb.org/t/p/w780\(backdrop)"
                }
                
                let movieDetails = item.movieDetails ?? MovieDetails(tmdbID: tmdbID)
                movieDetails.item = item
                movieDetails.runtime = details.runtime
                movieDetails.genres = details.genres
                movieDetails.voteAverage = details.voteAverage
                movieDetails.originalLanguage = details.originalLanguage
                movieDetails.creators = details.directors.map { $0.name }
                
                // Sync Cast
                for member in movieDetails.cast { modelContext.delete(member) }
                var newCastList: [CastMember] = []
                for c in details.cast {
                    let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                    let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                    member.movieDetails = movieDetails
                    modelContext.insert(member)
                    newCastList.append(member)
                }
                movieDetails.cast = newCastList
                
                if movieDetails.modelContext == nil { modelContext.insert(movieDetails) }
                
                item.lastUpdated = Date()
                
            } else if item.type == .tvShow, let tmdbID = Int(item.id) {
                let details = try await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
                
                // Phase 2 Optimization: Head-Only Smart Refresh
                let tvDetails = item.tvShowDetails ?? TVShowDetails(tmdbID: tmdbID)
                
                let isAlreadyCurrent = tvDetails.numberOfEpisodes == details.episodesCount && 
                                     tvDetails.status == details.status && 
                                     item.releaseDate != nil &&
                                     !metadataOnly &&
                                     !tvDetails.seasons.isEmpty
                
                if isAlreadyCurrent && item.state != .active {
                    // Just update a few key bits without full season sync
                    tvDetails.nextEpisodeDate = DateUtils.parseEpisodeDate(details.nextEpisodeDate, serviceName: tvDetails.network, for: tvDetails)
                    tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
                    tvDetails.nextSeasonNumber = details.nextSeasonNumber
                    item.lastUpdated = Date()
                    return true
                }

                // Nil-safe date update
                if let newDate = DateUtils.parseDate(details.firstAirDate) {
                    item.releaseDate = newDate
                }
                
                // Poster & Backdrop Upgrade
                if let poster = details.posterPath {
                    item.posterURL = "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(poster)"
                }
                if let backdrop = details.backdropPath {
                    item.backdropURL = "https://image.tmdb.org/t/p/w780\(backdrop)"
                }
                
                // Parallel Season Fetching
                var tvMazeID: Int? = nil
                
                if let tvdbID = details.tvdbID {
                    // Phase 2 Optimization: Persisted TVMaze ID
                    if let existingMazeID = tvDetails.tvMazeID {
                        tvMazeID = existingMazeID
                    } else if let mID = try? await APIClient.shared.lookupTVMazeID(tvdbID: tvdbID) {
                        tvMazeID = mID
                    }
                    
                    if let mID = tvMazeID {
                        if let (episode, timezone, service) = try? await APIClient.shared.fetchTVMazeSchedule(tvMazeID: mID), let schedule = episode {
                            tvDetails.nextEpisodeDate = DateUtils.parseFullDate(dateString: schedule.airdate, timeString: schedule.airtime, airstamp: schedule.airstamp, timezone: timezone, serviceName: service, item: item)
                        }
                        // We skip detailed episode fetch here as it's handled by TMDB seasons
                    }
                }

                // Update Cast
                for member in tvDetails.cast { modelContext.delete(member) }
                var newCastList: [CastMember] = []
                for c in details.cast {
                    let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                    let member = CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order)
                    member.tvShowDetails = tvDetails
                    modelContext.insert(member)
                    newCastList.append(member)
                }

                // Diff-based Sync
                if tvDetails.modelContext == nil { modelContext.insert(tvDetails) }
                tvDetails.item = item
                
                tvDetails.voteAverage = details.voteAverage
                tvDetails.genres = details.genres
                tvDetails.network = details.network
                tvDetails.networkLogoPath = details.networkLogoPath
                tvDetails.originalLanguage = details.originalLanguage
                tvDetails.status = details.status
                tvDetails.numberOfSeasons = details.seasonsCount
                tvDetails.numberOfEpisodes = details.episodesCount
                tvDetails.tvMazeID = tvMazeID
                tvDetails.nextEpisodeNumber = details.nextEpisodeNumber
                tvDetails.nextSeasonNumber = details.nextSeasonNumber
                tvDetails.creators = details.creators.map { $0.name }
                tvDetails.cast = newCastList
                
                if !metadataOnly {
                    for seasonData in details.seasons {
                        let sNum = seasonData.season_number
                        let season = tvDetails.seasons.first(where: { $0.seasonNumber == sNum }) ?? TVSeason(seasonNumber: sNum, name: seasonData.name, episodeCount: seasonData.episode_count, airDate: seasonData.air_date, showID: tmdbID)
                        
                        if season.modelContext == nil {
                            season.tvShowDetails = tvDetails
                            modelContext.insert(season)
                        }
                        
                        let episodes = try await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: sNum)
                        for ep in episodes {
                            let episode = season.episodes.first(where: { $0.episodeNumber == ep.episodeNumber }) ?? TVEpisode(episodeNumber: ep.episodeNumber, seasonNumber: sNum, name: ep.name, overview: ep.overview, airDate: ep.airDate, runtime: ep.runtime, showID: tmdbID)
                            
                            if episode.modelContext == nil {
                                episode.season = season
                                modelContext.insert(episode)
                            } else {
                                episode.name = ep.name
                                episode.overview = ep.overview
                                episode.airDate = ep.airDate
                            }
                        }
                    }
                }
                
                item.lastUpdated = Date()
            }
            
            item.syncCachedProperties()
            item.updateSearchableText()
            try modelContext.save()
            return true
        } catch {
            print("❌ Refresh error for \(item.title): \(error)")
            return false
        }
    }
}

@ModelActor
actor DiscoverySyncService {
    func syncLibrary(force: Bool) async {
        let descriptor = FetchDescriptor<MediaItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }
        
        // 1. Clear existing aggregates
        try? modelContext.delete(model: NetworkEntity.self)
        try? modelContext.delete(model: GenreEntity.self)
        try? modelContext.delete(model: LanguageEntity.self)
        
        var networks: [String: (logo: String?, count: Int)] = [:]
        var genres: [String: Int] = [:]
        var languages: [String: Int] = [:]
        
        for item in items {
            // Count Networks
            if item.type == .tvShow, let name = item.cachedNetwork {
                let current = networks[name] ?? (logo: item.cachedNetworkLogoPath, count: 0)
                networks[name] = (logo: current.logo, count: current.count + 1)
            }
            
            // Count Genres
            for genre in item.cachedGenres {
                genres[genre, default: 0] += 1
            }
            
            // Count Languages
            if let lang = item.cachedLanguage {
                languages[lang, default: 0] += 1
            }
        }
        
        // 2. Persist Discovery Entities
        for (name, data) in networks {
            modelContext.insert(NetworkEntity(name: name, logoPath: data.logo, count: data.count))
        }
        for (name, count) in genres {
            modelContext.insert(GenreEntity(name: name, count: count))
        }
        for (code, count) in languages {
            modelContext.insert(LanguageEntity(code: code, count: count))
        }
        
        try? modelContext.save()
        
        // 3. Extract missing colors (background task)
        await extractMissingColors()
    }

    func updateItemAdded(_ item: MediaItem) async {
        await syncLibrary(force: false)
    }

    func updateItemDeleted(network: String?, genres: [String], language: String?) async {
        if let name = network {
            let descriptor = FetchDescriptor<NetworkEntity>(predicate: #Predicate { $0.name == name })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.count -= 1
                if existing.count <= 0 { modelContext.delete(existing) }
            }
        }
        
        for genre in genres {
            let descriptor = FetchDescriptor<GenreEntity>(predicate: #Predicate { $0.name == genre })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.count -= 1
                if existing.count <= 0 { modelContext.delete(existing) }
            }
        }
        
        if let lang = language {
            let descriptor = FetchDescriptor<LanguageEntity>(predicate: #Predicate { $0.code == lang })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.count -= 1
                if existing.count <= 0 { modelContext.delete(existing) }
            }
        }
        
        try? modelContext.save()
    }

    private func extractMissingColors() async {
        let descriptor = FetchDescriptor<NetworkEntity>()
        guard let networks = try? modelContext.fetch(descriptor) else { return }
        
        for network in networks where network.themeColorHex == nil {
            guard let logo = network.logoPath, let url = URL(string: "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(logo)") else { continue }
            
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                // Phase 3 Optimization: Low-memory color extraction from raw data
                let color = ColorExtractor.dominantColor(from: data)
                network.themeColorHex = color.toHex()
                let name = network.name
                await MainActor.run { NetworkThemeManager.shared.save(color: color, for: name) }
            }
        }
        try? modelContext.save()
    }
}
