import Foundation
import SwiftData

struct ScopedStatsSections: OptionSet, Sendable, Hashable {
    let rawValue: UInt8

    static let actors = ScopedStatsSections(rawValue: 1 << 0)
    static let genres = ScopedStatsSections(rawValue: 1 << 1)
    static let networks = ScopedStatsSections(rawValue: 1 << 2)
    static let providers = ScopedStatsSections(rawValue: 1 << 3)
    static let languages = ScopedStatsSections(rawValue: 1 << 4)
    static let all: ScopedStatsSections = [.actors, .genres, .networks, .providers, .languages]

    static func visibleSections(for filterType: FilterType) -> ScopedStatsSections {
        switch filterType {
        case .genre:
            return [.actors, .networks, .providers, .languages]
        case .network, .studio:
            return [.actors, .genres, .providers, .languages]
        case .provider:
            return [.actors, .genres, .networks, .languages]
        case .language:
            return [.actors, .genres, .networks, .providers]
        case .badge, .onThisWeek:
            return .all
        }
    }
}

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

    func fetchScopedStats(
        filter: DiscoveryFilter,
        sections: ScopedStatsSections = .all
    ) async -> ScopedLibraryStats {
#if DEBUG
        let startedAt = Date()
#endif
        let sourceKey = filter.sourceNames?.sorted().joined(separator: "|") ?? ""
        let cacheKey = "\(filter.type.rawValue):\(filter.name):\(sourceKey):\(sections.rawValue)"
        if let cached = await ScopedStatsCache.shared.stats(forKey: cacheKey) {
#if DEBUG
            AppLogger.debug(
                "Scoped stats cache hit type=\(filter.type.rawValue) sections=\(sections.rawValue) duration=\(Int(Date().timeIntervalSince(startedAt) * 1_000))ms",
                logger: AppLogger.performance
            )
#endif
            return cached
        }
        guard !Task.isCancelled else { return .empty }

        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = [
            \.id, \.title,
            \.typeValue, \.tasteValue,
            \.cachedGenres, \.cachedLanguage, \.cachedNetwork,
            \.cachedWatchProviders, \.cachedRuntime, \.storedCast, \.cachedSeasonCount
        ]
        descriptor.fetchLimit = LibraryScanLimits.statsScanCap

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
        case .onThisWeek:
            descriptor.predicate = #Predicate { $0.isSoftDeleted == false && $0.releaseDate != nil }
        }

        guard var items = try? modelContext.fetch(descriptor) else {
            return ScopedLibraryStats.empty
        }
        guard !Task.isCancelled else { return .empty }

        if filter.type == .genre {
            items = items.filter { $0.cachedGenres.contains(name) }
        }

        if filter.type == .onThisWeek {
            let now = Date()
            items = items.filter { item in
                guard let d = item.releaseDate else { return false }
                return DateUtils.sameWeek(d, now)
            }
        }

        guard !items.isEmpty else {
            return ScopedLibraryStats.empty
        }

        let networkNames = filter.type == .network || filter.type == .studio
            ? Set((filter.sourceNames ?? [filter.name]).map { $0.lowercased() })
            : nil
        let providerName = filter.type == .provider ? filter.name : nil

        // Apply every scope-specific refinement before calculating totals or
        // metadata. Previously network/provider scopes counted their broad SQL
        // candidate set in `totalItems`, while their cards used a narrower set.
        let matchedItems = items.filter { item in
            if let networkNames, let rawNetworks = item.cachedNetwork {
                let itemNetworks = rawNetworks.commaSeparatedValues.map { $0.lowercased() }
                guard itemNetworks.contains(where: networkNames.contains) else { return false }
            } else if networkNames != nil {
                return false
            }

            if let providerName {
                guard item.cachedWatchProviders.contains(providerName) else { return false }
            }
            return true
        }

        guard !matchedItems.isEmpty else {
            return ScopedLibraryStats.empty
        }

        // Build source→target aliases only when the visible header needs
        // network aggregation.
        let aliasMap: [String: String]
        if sections.contains(.networks) {
            let aliasEntities = (try? modelContext.fetch(FetchDescriptor<StudioAliasEntity>())) ?? []
            aliasMap = DiscoverySyncService.buildSourceToTargetMap(from: aliasEntities)
        } else {
            aliasMap = [:]
        }

        var actorTaste: [String: CategoryStats] = [:]
        var genreTaste: [String: CategoryStats] = [:]
        var networkCounts: [String: Int] = [:]
        var providerCounts: [String: Int] = [:]
        var languageCounts: [String: Int] = [:]
        var totalRuntime = 0

        for item in matchedItems {
            guard !Task.isCancelled else { return .empty }
            totalRuntime += item.cachedRuntime ?? 0

            let titleWeight = TasteMath.titleWeight(for: item)

            // Actors — pick top 5 cast per title for cross-title affinity
            if sections.contains(.actors) {
                TasteMath.accumulateTopBilledCast(&actorTaste, cast: item.displayCast, taste: item.tasteValue, limit: 5, weight: titleWeight)
            }

            // Genres
            if sections.contains(.genres) {
                TasteMath.accumulateGenres(&genreTaste, genres: item.cachedGenres, taste: item.tasteValue, weight: titleWeight)
            }

            // Networks — grouped by alias target
            if sections.contains(.networks), let rawNetwork = item.cachedNetwork {
                for n in rawNetwork.commaSeparatedValues {
                    let groupedName = aliasMap[n.lowercased()] ?? n
                    networkCounts[groupedName, default: 0] += 1
                }
            }

            // Providers — raw count
            if sections.contains(.providers) {
                for p in item.cachedWatchProviders where !p.isEmpty {
                    providerCounts[p, default: 0] += 1
                }
            }

            // Languages — raw count
            if sections.contains(.languages), let lang = item.cachedLanguage, !lang.isEmpty {
                languageCounts[lang, default: 0] += 1
            }
        }

        // Affinity-based: actors (cutoff 3), genres (cutoff 5)
        let topActors: [ScoredPerson] = sections.contains(.actors) ? actorTaste.compactMap { actorName, val in
            let score = val.affinity(cutoff: 3)
            guard score > 0 else { return nil }
            return ScoredPerson(id: actorName, name: actorName, score: score, count: val.total, profileURL: val.profileURL)
        }.sorted { TasteMath.compareByAffinityCountName(($0.score, $0.count, $0.name), ($1.score, $1.count, $1.name)) }.prefix(6).map { $0 } : []

        let topGenres: [(name: String, score: Double)] = sections.contains(.genres) ? genreTaste.compactMap { genreName, val -> (String, Double, Int)? in
            let score = val.affinity(cutoff: 5)
            guard score > 0 else { return nil }
            return (genreName, score, val.total)
        }.sorted { TasteMath.compareByAffinityCountName(($0.1, $0.2, $0.0), ($1.1, $1.2, $1.0)) }.prefix(8).map { ($0.0, $0.1) } : []

        // Count-based: networks, providers, languages (alpha tie-break on equal counts)
        let topNetworks = sections.contains(.networks) ? networkCounts.sorted {
            $0.1 == $1.1 ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending : $0.1 > $1.1
        }.prefix(8).map { ($0.0, $0.1) } : []
        let topProviders = sections.contains(.providers) ? providerCounts.sorted {
            $0.1 == $1.1 ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending : $0.1 > $1.1
        }.prefix(8).map { ($0.0, $0.1) } : []
        let topLanguages = sections.contains(.languages) ? languageCounts.sorted {
            $0.1 == $1.1 ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending : $0.1 > $1.1
        }.prefix(8).map { ($0.0, $0.1) } : []

        let result = ScopedLibraryStats(
            totalItems: matchedItems.count,
            totalRuntime: totalRuntime,
            topActors: topActors,
            topGenres: topGenres,
            topNetworks: topNetworks,
            topProviders: topProviders,
            topLanguages: topLanguages
        )

        await ScopedStatsCache.shared.setStats(result, forKey: cacheKey)
#if DEBUG
        AppLogger.debug(
            "Scoped stats type=\(filter.type.rawValue) candidates=\(items.count) matched=\(matchedItems.count) sections=\(sections.rawValue) duration=\(Int(Date().timeIntervalSince(startedAt) * 1_000))ms",
            logger: AppLogger.performance
        )
#endif
        return result
    }
}

@MainActor
class ScopedStatsCache {
    static let shared = ScopedStatsCache()
    private var cache: [String: ScopedLibraryStats] = [:]
    private var accessOrder: [String] = []
    private let capacity = 24

    func stats(forKey key: String) -> ScopedLibraryStats? {
        guard let stats = cache[key] else { return nil }
        touch(key)
        return stats
    }

    func setStats(_ stats: ScopedLibraryStats, forKey key: String) {
        cache[key] = stats
        touch(key)

        while accessOrder.count > capacity {
            let oldestKey = accessOrder.removeFirst()
            cache.removeValue(forKey: oldestKey)
        }
    }

    func invalidateAll() {
        cache.removeAll()
        accessOrder.removeAll()
    }

    private func touch(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }
}

extension ScopedStatsActor {
    nonisolated static func invalidateCache() {
        Task { @MainActor in ScopedStatsCache.shared.invalidateAll() }
    }
}
