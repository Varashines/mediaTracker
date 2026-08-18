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
            \.cachedWatchProviders, \.cachedRuntime, \.storedCast, \.cachedSeasonCount
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
        case .onThisDay:
            descriptor.predicate = #Predicate { $0.isSoftDeleted == false && $0.releaseDate != nil }
        }

        guard var items = try? modelContext.fetch(descriptor) else {
            return ScopedLibraryStats.empty
        }

        // Build source→target alias map so network/studio counting matches hub grouping.
        let aliasEntities = (try? modelContext.fetch(FetchDescriptor<StudioAliasEntity>())) ?? []
        let aliasMap = DiscoverySyncService.buildSourceToTargetMap(from: aliasEntities)

        if filter.type == .genre {
            items = items.filter { $0.cachedGenres.contains(name) }
        }

        if filter.type == .onThisDay {
            let now = Date()
            items = items.filter { item in
                guard let d = item.releaseDate else { return false }
                return DateUtils.sameMonthDay(d, now)
            }
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
                let itemNets = rawNets.commaSeparatedValues.map { $0.lowercased() }
                guard itemNets.contains(where: { nSet.contains($0) }) else { continue }
            }
            if let pName = providerName {
                guard item.cachedWatchProviders.contains(pName) else { continue }
            }

            totalRuntime += item.cachedRuntime ?? 0

            let titleWeight = TasteMath.titleWeight(for: item)

            // Actors — pick top 5 cast per title for cross-title affinity
            TasteMath.accumulateTopBilledCast(&actorTaste, cast: item.displayCast, taste: item.tasteValue, limit: 5, weight: titleWeight)

            // Genres
            TasteMath.accumulateGenres(&genreTaste, genres: item.cachedGenres, taste: item.tasteValue, weight: titleWeight)

            // Networks — grouped by alias target
            if let rawNetwork = item.cachedNetwork {
                for n in rawNetwork.commaSeparatedValues {
                    let groupedName = aliasMap[n.lowercased()] ?? n
                    networkCounts[groupedName, default: 0] += 1
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
        }.sorted { TasteMath.compareByAffinityCountName(($0.score, $0.count, $0.name), ($1.score, $1.count, $1.name)) }.prefix(6).map { $0 }

        let topGenres: [(name: String, score: Double)] = genreTaste.compactMap { genreName, val -> (String, Double, Int)? in
            let score = val.affinity(cutoff: 5)
            guard score > 0 else { return nil }
            return (genreName, score, val.total)
        }.sorted { TasteMath.compareByAffinityCountName(($0.1, $0.2, $0.0), ($1.1, $1.2, $1.0)) }.prefix(8).map { ($0.0, $0.1) }

        // Count-based: networks, providers, languages (alpha tie-break on equal counts)
        let topNetworks = networkCounts.sorted {
            $0.1 == $1.1 ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending : $0.1 > $1.1
        }.prefix(8).map { ($0.0, $0.1) }
        let topProviders = providerCounts.sorted {
            $0.1 == $1.1 ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending : $0.1 > $1.1
        }.prefix(8).map { ($0.0, $0.1) }
        let topLanguages = languageCounts.sorted {
            $0.1 == $1.1 ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending : $0.1 > $1.1
        }.prefix(8).map { ($0.0, $0.1) }

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
