import Foundation
import SwiftData
import SwiftUI

@ModelActor
actor DiscoverySyncService {
    private struct AliasRule {
        let target: String
        let sources: Set<String>
        let preferredLogoSource: String?
    }
    
    @MainActor private static var cachedRules: [AliasRule]?

    private func fetchAliasRules() async -> [AliasRule] {
        // Simple cache check to avoid redundant fetches in the same sync loop
        if let cached = await MainActor.run(body: { Self.cachedRules }) {
            return cached
        }

        let descriptor = FetchDescriptor<StudioAliasEntity>()
        let entities = (try? modelContext.fetch(descriptor)) ?? []
        
        // One-time migration check
        if entities.isEmpty {
            let legacy = UserDefaults.standard.string(forKey: "studio_aliases") ?? ""
            if !legacy.isEmpty {
                let rules = migrateLegacyAliases(legacy)
                for rule in rules {
                    modelContext.insert(StudioAliasEntity(target: rule.target, sources: Array(rule.sources), preferredLogoSource: rule.preferredLogoSource))
                }
                try? modelContext.save()
                return rules
            }
        }

        let rules = entities.map { AliasRule(target: $0.target, sources: Set($0.sources), preferredLogoSource: $0.preferredLogoSource) }
        await MainActor.run { Self.cachedRules = rules }
        return rules
    }

    private func migrateLegacyAliases(_ legacy: String) -> [AliasRule] {
        let lines = legacy.components(separatedBy: .newlines)
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
        // Clear cache at start of sync
        await MainActor.run { Self.cachedRules = nil }
        var networkCounts: [String: (logo: String?, count: Int, priority: Int, sources: [String])] = [:]
        var genreCounts: [String: Int] = [:]
        var languageCounts: [String: Int] = [:]
        var badgeCounts: [String: Int] = [:]
        
        let batchSize = 500
        var offset = 0
        
        while true {
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            
            guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { break }

            // Studio Aliases (Cached internally in fetchAliasRules)
            let rules = await fetchAliasRules()
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
            
            for item in items {
                // Count Networks
                if item.type == .tvShow, let originalName = item.cachedNetwork {
                    let targetName: String = sourceToTarget[originalName] ?? originalName
                    let preferredSource: String? = targetToLogoSource[targetName]
                    
                    let currentData = networkCounts[targetName] ?? (logo: nil, count: 0, priority: 0, sources: [])
                    var newLogo: String? = currentData.logo
                    var newPriority: Int = currentData.priority
                    var newSources: [String] = currentData.sources
                    
                    if !newSources.contains(originalName) {
                        newSources.append(originalName)
                    }
                    
                    if let itemLogo = item.cachedNetworkLogoPath {
                        let isPreferredSource = (preferredSource != nil && originalName == preferredSource)
                        let isMainSource = (originalName == targetName)
                        
                        if isPreferredSource {
                            newLogo = itemLogo
                            newPriority = 100
                        } else if newLogo == nil || (isMainSource && newPriority < 50) {
                            newLogo = itemLogo
                            newPriority = isMainSource ? 50 : 10
                        }
                    }
                    
                    networkCounts[targetName] = (logo: newLogo, count: currentData.count + 1, priority: newPriority, sources: newSources)
                }
                
                // Count Genres
                for genre in item.cachedGenres {
                    genreCounts[genre, default: 0] += 1
                }
                
                // Count Languages
                if let lang = item.cachedLanguage {
                    languageCounts[lang, default: 0] += 1
                }

                // Count Badges
                if let badge = item.storedSmartBadgeLabel {
                    badgeCounts[badge, default: 0] += 1
                }
            }
            
            offset += batchSize
            // Clear context objects to free memory
            modelContext.processPendingChanges()
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

        let existingBadges = (try? modelContext.fetch(FetchDescriptor<BadgeEntity>())) ?? []
        for (label, count) in badgeCounts {
            if let existing = existingBadges.first(where: { $0.label == label }) {
                existing.count = count
            } else {
                modelContext.insert(BadgeEntity(label: label, count: count))
            }
        }
        for entity in existingBadges where badgeCounts[entity.label] == nil {
            modelContext.delete(entity)
        }
        
        try? modelContext.save()
        
        // 3. Extract missing colors
        await extractMissingColors()
    }

    func updateItemAdded(_ item: MediaItem) async {
        // Studio Aliases
        let rules = await fetchAliasRules()
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

        // Incremental Badge update
        if let badge = item.storedSmartBadgeLabel {
            let descriptor = FetchDescriptor<BadgeEntity>(predicate: #Predicate { $0.label == badge })
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.count += 1
            } else {
                modelContext.insert(BadgeEntity(label: badge, count: 1))
            }
        }
        
        try? modelContext.save()
        
        // Ensure colors are updated for the new network
        await extractMissingColors()
    }

    func updateItemDeleted(network: String?, genres: [String], language: String?, badge: String?) async {
        // Studio Aliases
        let rules = await fetchAliasRules()
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

        if let b = badge {
            let descriptor = FetchDescriptor<BadgeEntity>(predicate: #Predicate { $0.label == b })
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

        let missing = networks.filter { $0.themeColorHex == nil }
        if missing.isEmpty { return }

        await withTaskGroup(of: (PersistentIdentifier, String?).self) { group in
            for network in missing {
                let id: PersistentIdentifier = network.persistentModelID
                let name: String = network.name
                let logoPath: String? = network.logoPath

                group.addTask {
                    // 1. Try Local Theme Manager Cache
                    let cachedHex: String? = await MainActor.run { 
                        NetworkThemeManager.shared.color(for: name)?.toHex() 
                    }
                    if let hex = cachedHex {
                        return (id, hex)
                    }

                    // 2. Fetch Logo and Extract Color
                    guard let path = logoPath,
                          let urlString = APIClient.tmdbImageURL(path: path, size: "w92"),
                          let url = URL(string: urlString) else {
                        return (id, nil)
                    }

                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let extractedColor = await ColorExtractor.dominantColor(from: data)
                        let hexString = extractedColor.toHex()
                        
                        // Update cache for future use
                        await MainActor.run { 
                            NetworkThemeManager.shared.save(color: extractedColor, for: name) 
                        }
                        return (id, hexString)
                    } catch {
                        return (id, nil)
                    }
                }
            }

            for await (id, hex) in group {
                if let hexValue = hex, let network = modelContext.model(for: id) as? NetworkEntity {
                    network.themeColorHex = hexValue
                }
            }
        }

        try? modelContext.save()
    }
}
