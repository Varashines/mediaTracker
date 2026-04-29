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
        
        // 0. Deduplicate MediaItems (Ensures no two items share the same TMDB ID)
        let groupedItems = Dictionary(grouping: items, by: { $0.id })
        for (id, duplicates) in groupedItems where duplicates.count > 1 {
            print("🔍 Maintenance: Found \(duplicates.count) duplicates for ID \(id)")
            let sorted = duplicates.sorted { 
                let score1 = ($0.posterURL != nil ? 2 : 0) + ($0.tvShowDetails != nil ? 5 : 0)
                let score2 = ($1.posterURL != nil ? 2 : 0) + ($1.tvShowDetails != nil ? 5 : 0)
                if score1 != score2 { return score1 > score2 }
                return ($0.lastInteractionDate ?? .distantPast) > ($1.lastInteractionDate ?? .distantPast)
            }
            // Keep the best one, delete the rest
            for i in 1..<sorted.count {
                modelContext.delete(sorted[i])
            }
        }
        
        // Fetch fresh list after deduplication
        let sanitizedItems = (try? modelContext.fetch(descriptor)) ?? []
        
        for item in sanitizedItems {
            // 1. Migrate legacy IDs to prefixed format (prevents Movie/TV collisions)
            if !item.id.contains("_") {
                let typePrefix = item.type == .movie ? "movie" : "tv"
                item.id = "\(typePrefix)_\(item.id)"
            }

            // 2. Assign uniqueIDs to episodes
            if let tmdbIDString = item.id.split(separator: "_").last, let tmdbID = Int(tmdbIDString) {
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
                        
                        // 3. Remove duplicate episodes within the same season
                        let grouped = Dictionary(grouping: season.episodes, by: { $0.episodeNumber })
                        for (_, eps) in grouped where eps.count > 1 {
                            // Keep the one with the most data
                            let sorted = eps.sorted { ($0.airDate ?? "").count > ($1.airDate ?? "").count }
                            for i in 1..<sorted.count {
                                modelContext.delete(sorted[i])
                            }
                        }
                    }
                    
                    // 4. Purge legacy Crew cards
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
            item.syncCachedProperties()
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
    
    /// Batch Queue for coalescing metadata refresh requests
    private var pendingRefreshIDs = Set<String>()
    private var refreshTask: Task<Void, Never>?

    /// Tracks items currently being added to prevent race conditions and duplicates.
    private var itemsInProgress = Set<String>()

    // Feedback State
    var isRunningMaintenance = false
    var showMaintenanceComplete = false

    func isProcessing(id: String) -> Bool { itemsInProgress.contains(id) }
    func startProcessing(id: String) { itemsInProgress.insert(id) }
    func stopProcessing(id: String) { itemsInProgress.remove(id) }

    func hasRefreshedThisSession(id: String) -> Bool {
        return sessionRefreshedItems.contains(id)
    }

    func markAsRefreshedThisSession(id: String) {
        sessionRefreshedItems.insert(id)
    }

    func refreshMetadata(for items: [MediaItem], modelContext: ModelContext, metadataOnly: Bool = false, force: Bool = false, skipDelay: Bool = false) {
        // Skip if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        let itemIDs = items.map { $0.id }

        // Phase 4 Optimization: Coalesce into Batch Queue
        pendingRefreshIDs.formUnion(itemIDs)
        refreshTask?.cancel()
        refreshTask = Task {
            // Wait for potential rapid-fire calls to finish (e.g. during an import or scroll)
            if !skipDelay {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            }
            if Task.isCancelled { return }
            
            let idsToProcess = Array(pendingRefreshIDs)
            pendingRefreshIDs.removeAll()
            
            if !idsToProcess.isEmpty {
                let backgroundService = BackgroundDataService(modelContainer: modelContext.container)
                await backgroundService.refreshMetadata(for: idsToProcess, metadataOnly: metadataOnly, force: force)
            }
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
                        let typePrefix = itemData.type.lowercased().contains("movie") ? "movie" : "tv"
                        let uniqueID = "\(typePrefix)_\(itemData.id.split(separator: "_").last ?? itemData.id[...])"
                        let key = "\(uniqueID)_\(itemData.type)"
                        
                        if !existingKeys.contains(key) {
                            let item = MediaItem(
                                id: uniqueID,
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

@ModelActor
actor DiscoverySyncService {
    private struct AliasRule {
        let target: String
        let sources: Set<String>
        let preferredLogoSource: String?
    }

    private func parseAliases() -> [AliasRule] {
        let aliasString = UserDefaults.standard.string(forKey: "studio_aliases") ?? ""
        let lines = aliasString.components(separatedBy: .newlines)
        var rules: [AliasRule] = []
        
        for line in lines where line.contains("=") {
            let mainParts = line.components(separatedBy: "|")
            let aliasPart = mainParts[0]
            let logoPart = mainParts.count > 1 ? mainParts[1] : nil
            
            let sides = aliasPart.components(separatedBy: "=")
            guard sides.count >= 2 else { continue }
            
            let target = sides[0].trimmingCharacters(in: .whitespaces)
            let sources = sides[1].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
            var preferredLogoSource: String? = nil
            if let logoStr = logoPart, logoStr.contains("Logo:") {
                preferredLogoSource = logoStr.components(separatedBy: "Logo:").last?.trimmingCharacters(in: .whitespaces)
            }
            
            rules.append(AliasRule(target: target, sources: Set(sources), preferredLogoSource: preferredLogoSource))
        }
        return rules
    }

    func syncLibrary(force: Bool) async {
        let descriptor = FetchDescriptor<MediaItem>()
        guard let items = try? modelContext.fetch(descriptor) else { return }
        
        // Studio Aliases
        let rules = parseAliases()
        var sourceToTarget: [String: String] = [:]
        var targetToLogoSource: [String: String] = [:]
        
        for rule in rules {
            for source in rule.sources {
                sourceToTarget[source] = rule.target
            }
            if let pref = rule.preferredLogoSource {
                targetToLogoSource[rule.target] = pref
            }
        }
        
        var networkCounts: [String: (logo: String?, count: Int, priority: Int, sources: [String])] = [:]
        var genreCounts: [String: Int] = [:]
        var languageCounts: [String: Int] = [:]
        
        for item in items {
            // Count Networks
            if item.type == .tvShow, let originalName = item.cachedNetwork {
                let name = sourceToTarget[originalName] ?? originalName
                let preferredSource = targetToLogoSource[name]
                
                let current = networkCounts[name] ?? (logo: nil, count: 0, priority: 0, sources: [])
                var newLogo = current.logo
                var newPriority = current.priority
                var newSources = current.sources
                if !newSources.contains(originalName) { newSources.append(originalName) }
                
                if let itemLogo = item.cachedNetworkLogoPath {
                    if let pref = preferredSource, originalName == pref {
                        newLogo = itemLogo
                        newPriority = 100
                    } else if newLogo == nil || (originalName == name && newPriority < 50) {
                        newLogo = itemLogo
                        newPriority = (originalName == name) ? 50 : 10
                    }
                }
                
                networkCounts[name] = (logo: newLogo, count: current.count + 1, priority: newPriority, sources: newSources)
            }
            
            // Count Genres
            for genre in item.cachedGenres {
                genreCounts[genre, default: 0] += 1
            }
            
            // Count Languages
            if let lang = item.cachedLanguage {
                languageCounts[lang, default: 0] += 1
            }
        }
        
        // 2. Incremental Sync: Update existing, insert new, delete orphaned
        let existingNetworks = (try? modelContext.fetch(FetchDescriptor<NetworkEntity>())) ?? []
        for (name, data) in networkCounts {
            if let existing = existingNetworks.first(where: { $0.name == name }) {
                existing.count = data.count
                existing.logoPath = data.logo
                existing.sourceNames = data.sources
            } else {
                modelContext.insert(NetworkEntity(name: name, logoPath: data.logo, count: data.count, sourceNames: data.sources))
            }
        }
        for entity in existingNetworks where networkCounts[entity.name] == nil {
            modelContext.delete(entity)
        }

        let existingGenres = (try? modelContext.fetch(FetchDescriptor<GenreEntity>())) ?? []
        for (name, count) in genreCounts {
            if let existing = existingGenres.first(where: { $0.name == name }) {
                existing.count = count
            } else {
                modelContext.insert(GenreEntity(name: name, count: count))
            }
        }
        for entity in existingGenres where genreCounts[entity.name] == nil {
            modelContext.delete(entity)
        }

        let existingLanguages = (try? modelContext.fetch(FetchDescriptor<LanguageEntity>())) ?? []
        for (code, count) in languageCounts {
            if let existing = existingLanguages.first(where: { $0.code == code }) {
                existing.count = count
            } else {
                modelContext.insert(LanguageEntity(code: code, count: count))
            }
        }
        for entity in existingLanguages where languageCounts[entity.code] == nil {
            modelContext.delete(entity)
        }
        
        try? modelContext.save()
        
        // 3. Extract missing colors
        await extractMissingColors()
    }

    func updateItemAdded(_ item: MediaItem) async {
        // Studio Aliases
        let rules = parseAliases()
        var sourceToTarget: [String: String] = [:]
        for rule in rules {
            for source in rule.sources {
                sourceToTarget[source] = rule.target
            }
        }

        // Incremental Network update
        if item.type == .tvShow, let originalName = item.cachedNetwork {
            let name = sourceToTarget[originalName] ?? originalName
            let descriptor = FetchDescriptor<NetworkEntity>(predicate: #Predicate { $0.name == name })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.count += 1
            } else {
                modelContext.insert(NetworkEntity(name: name, logoPath: item.cachedNetworkLogoPath, count: 1))
            }
        }
        
        // ... (rest of function unchanged)
        for genre in item.cachedGenres {
            let descriptor = FetchDescriptor<GenreEntity>(predicate: #Predicate { $0.name == genre })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.count += 1
            } else {
                modelContext.insert(GenreEntity(name: genre, count: 1))
            }
        }
        
        // Incremental Language update
        if let lang = item.cachedLanguage {
            let descriptor = FetchDescriptor<LanguageEntity>(predicate: #Predicate { $0.code == lang })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.count += 1
            } else {
                modelContext.insert(LanguageEntity(code: lang, count: 1))
            }
        }
        
        try? modelContext.save()
        
        // Ensure colors are updated for the new network
        await extractMissingColors()
    }

    func updateItemDeleted(network: String?, genres: [String], language: String?) async {
        // Studio Aliases
        let rules = parseAliases()
        var sourceToTarget: [String: String] = [:]
        for rule in rules {
            for source in rule.sources {
                sourceToTarget[source] = rule.target
            }
        }

        if let originalName = network {
            let name = sourceToTarget[originalName] ?? originalName
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
            let name = network.name
            // Restore from cache if available
            let cachedColor = await MainActor.run { NetworkThemeManager.shared.color(for: name) }
            if let cachedColor = cachedColor {
                network.themeColorHex = cachedColor.toHex()
                continue
            }
            
            guard let logo = network.logoPath, let url = URL(string: "https://image.tmdb.org/t/p/\(APIClient.shared.idealThumbnailSize)\(logo)") else { continue }
            
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                // Phase 3 Optimization: Low-memory color extraction from raw data
                let color = await ColorExtractor.dominantColor(from: data)
                network.themeColorHex = color.toHex()
                await MainActor.run { NetworkThemeManager.shared.save(color: color, for: name) }
            }
        }
        try? modelContext.save()
    }
}
