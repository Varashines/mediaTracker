import Foundation
import SwiftData

struct ScopedLibraryStats: Sendable {
    let totalItems: Int
    let totalRuntime: Int
    let topActors: [ScoredPerson]
    let topGenres: [(name: String, score: Double)]
    let topNetworks: [(name: String, count: Int)]
    let topProviders: [(name: String, count: Int)]
    let topLanguages: [(name: String, count: Int)]

    static let empty = ScopedLibraryStats(
        totalItems: 0, totalRuntime: 0,
        topActors: [], topGenres: [],
        topNetworks: [], topProviders: [],
        topLanguages: []
    )
}

struct ScoredPerson: Sendable, Identifiable {
    let id: String
    let name: String
    let score: Double
    let count: Int
    let profileURL: String?
}

@ModelActor
actor ScopedStatsActor {
    nonisolated static func shared(modelContainer: ModelContainer) -> ScopedStatsActor {
        ScopedStatsActor(modelContainer: modelContainer)
    }

    func fetchScopedStats(filter: DiscoveryFilter) async -> ScopedLibraryStats {
        let cacheKey = "\(filter.type.rawValue):\(filter.name)"
        if let cached = await ScopedStatsCache.shared.stats(forKey: cacheKey) { return cached }

        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = [
            \.id, \.title,
            \.typeValue, \.tasteValue,
            \.cachedGenres, \.cachedLanguage, \.cachedNetwork,
            \.cachedWatchProviders, \.cachedRuntime, \.storedCast
        ]
        descriptor.fetchLimit = 2000

        let name = filter.name
        switch filter.type {
        case .genre:
            // Do not use contains on cachedGenres in SQL predicate as it crashes on translation.
            // Fetch everything (or filtered by isSoftDeleted == false) and filter in memory.
            descriptor.predicate = #Predicate { $0.isSoftDeleted == false }
        case .language:
            let langName = LanguageUtils.languageName(for: name)
            descriptor.predicate = #Predicate { $0.isSoftDeleted == false && ($0.cachedLanguage == name || $0.cachedLanguage == langName) }
        case .network, .studio:
            descriptor.predicate = #Predicate { $0.isSoftDeleted == false && $0.cachedNetwork != nil }
        case .badge:
            descriptor.predicate = #Predicate { $0.isSoftDeleted == false && $0.storedSmartBadgeLabel == name }
        case .provider:
            descriptor.predicate = #Predicate { $0.isSoftDeleted == false }
        }

        guard var items = try? modelContext.fetch(descriptor) else {
            return ScopedLibraryStats.empty
        }

        if filter.type == .genre {
            items = items.filter { $0.cachedGenres.contains(name) }
        }

        guard !items.isEmpty else {
            return ScopedLibraryStats.empty
        }

        let networkNames = filter.type == .network || filter.type == .studio
            ? Set((filter.sourceNames ?? [filter.name]).map { $0.lowercased() })
            : nil
        let providerName = filter.type == .provider ? filter.name : nil

        var actorTaste: [String: CategoryStats] = [:]
        var genreTaste: [String: CategoryStats] = [:]
        var networkCounts: [String: Int] = [:]
        var providerCounts: [String: Int] = [:]
        var languageCounts: [String: Int] = [:]
        var totalRuntime = 0

        for item in items {
            if let nSet = networkNames, let rawNets = item.cachedNetwork {
                let itemNets = rawNets.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                guard itemNets.contains(where: { nSet.contains($0) }) else { continue }
            }
            if let pName = providerName {
                guard item.cachedWatchProviders.contains(pName) else { continue }
            }

            totalRuntime += item.cachedRuntime ?? 0

            // Actors — pick top 5 cast per title for cross-title affinity
            for actor in item.displayCast.prefix(5) {
                TasteMath.updateTaste(&actorTaste, actor.name, item.tasteValue, profileURL: actor.profileURL)
            }

            // Genres
            for g in item.cachedGenres {
                TasteMath.updateTaste(&genreTaste, g, item.tasteValue)
            }

            // Networks — raw count
            if let rawNetwork = item.cachedNetwork {
                for n in rawNetwork.components(separatedBy: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) where !n.isEmpty {
                    networkCounts[n, default: 0] += 1
                }
            }

            // Providers — raw count
            for p in item.cachedWatchProviders where !p.isEmpty {
                providerCounts[p, default: 0] += 1
            }

            // Languages — raw count
            if let lang = item.cachedLanguage, !lang.isEmpty {
                languageCounts[lang, default: 0] += 1
            }
        }

        // Affinity-based: actors (cutoff 3), genres (cutoff 5)
        let topActors: [ScoredPerson] = actorTaste.compactMap { actorName, val in
            let score = val.affinity(cutoff: 3)
            guard score > 0 else { return nil }
            return ScoredPerson(id: actorName, name: actorName, score: score, count: val.total, profileURL: val.profileURL)
        }.sorted { $0.score > $1.score }.prefix(6).map { $0 }

        let topGenres: [(name: String, score: Double)] = genreTaste.compactMap { genreName, val in
            let score = val.affinity(cutoff: 5)
            guard score > 0 else { return nil }
            return (genreName, score)
        }.sorted { $0.1 > $1.1 }.prefix(8).map { $0 }

        // Count-based: networks, providers, languages
        let topNetworks = networkCounts.sorted { $0.1 > $1.1 }.prefix(8).map { ($0.0, $0.1) }
        let topProviders = providerCounts.sorted { $0.1 > $1.1 }.prefix(8).map { ($0.0, $0.1) }
        let topLanguages = languageCounts.sorted { $0.1 > $1.1 }.prefix(8).map { ($0.0, $0.1) }

        let result = ScopedLibraryStats(
            totalItems: items.count,
            totalRuntime: totalRuntime,
            topActors: topActors,
            topGenres: topGenres,
            topNetworks: topNetworks,
            topProviders: topProviders,
            topLanguages: topLanguages
        )

        await ScopedStatsCache.shared.setStats(result, forKey: cacheKey)
        return result
    }
}

@MainActor
class ScopedStatsCache {
    static let shared = ScopedStatsCache()
    private var cache: [String: ScopedLibraryStats] = [:]

    func stats(forKey key: String) -> ScopedLibraryStats? { cache[key] }
    func setStats(_ stats: ScopedLibraryStats, forKey key: String) { cache[key] = stats }
    func invalidateAll() { cache.removeAll() }
}

extension ScopedStatsActor {
    nonisolated static func invalidateCache() {
        Task { @MainActor in ScopedStatsCache.shared.invalidateAll() }
    }
}
