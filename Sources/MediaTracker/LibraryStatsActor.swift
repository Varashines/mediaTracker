import Foundation
import SwiftData

struct VisualPersonStat: Sendable {
    let name: String
    let profileURL: String?
    let score: Double
    let count: Int
}

struct LibraryStats: Sendable {
    let totalWatchTimeMinutes: Int

    let totalMovies: Int
    let completedMovies: Int

    let totalTVShows: Int
    let completedTVShows: Int

    let totalEpisodesWatched: Int

    // Genre DNA (for Radar Chart)
    let genreDNA: [(name: String, percentage: Double)]

    // Visual Hall of Fame (Highest Rated, min 5 titles)
    let topRatedActors: [VisualPersonStat]
    let topRatedCreators: [VisualPersonStat]
    let topRatedGenres: [(name: String, score: Double)]
    let topRatedNetworks: [(name: String, score: Double)]
    let topRatedLanguages: [(name: String, score: Double)]

    let lovedCount: Int
    let likedCount: Int
    let dislikedCount: Int

    static let empty = LibraryStats(
        totalWatchTimeMinutes: 0,
        totalMovies: 0,
        completedMovies: 0,
        totalTVShows: 0,
        completedTVShows: 0,
        totalEpisodesWatched: 0,
        genreDNA: [],
        topRatedActors: [],
        topRatedCreators: [],
        topRatedGenres: [],
        topRatedNetworks: [],
        topRatedLanguages: [],
        lovedCount: 0,
        likedCount: 0,
        dislikedCount: 0
    )
}

@ModelActor
actor LibraryStatsActor {
    @MainActor private static var cachedStats: LibraryStats?
    @MainActor private static var lastCalculation: Date?
    private let cacheTTL: TimeInterval = 3600  // 1 hour

    // Taste Affinity Helpers
    struct CategoryStats: Sendable {
        var loved = 0
        var liked = 0
        var disliked = 0
        var total = 0
        var profileURL: String? = nil

        var ratedCount: Int { loved + liked + disliked }

        func affinity(cutoff: Int = 5) -> Double {
            guard ratedCount >= cutoff else { return -1.0 }
            let lovedWeight = Double(3 * loved)
            let likedWeight = Double(liked)
            let dislikedWeight = Double(2 * disliked)
            let totalWeight = Double(3 * ratedCount)
            let score = (lovedWeight + likedWeight - dislikedWeight) / totalWeight
            return max(0, score)
        }
    }

    private struct PersonInput: Sendable {
        let name: String
        let stats: CategoryStats
    }

    func fetchStats() async -> LibraryStats {
        // Check cache
        let (cached, last) = await MainActor.run { (Self.cachedStats, Self.lastCalculation) }
        if let cached = cached, let last = last, Date().timeIntervalSince(last) < cacheTTL {
            return cached
        }

        var statsContainer = RawStatsContainer()
        var tasteMaps = TasteMapsContainer()

        // Phase 5 Optimization: Batched Processing to prevent memory exhaustion
        let batchSize = 500
        var offset = 0
        
        while true {
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            
            guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { break }
            
            processBatch(items, stats: &statsContainer, taste: &tasteMaps)
            
            offset += batchSize
            modelContext.processPendingChanges()
        }

        let result = await finalizeStats(stats: statsContainer, taste: tasteMaps)

        await MainActor.run {
            Self.cachedStats = result
            Self.lastCalculation = Date()
        }

        return result
    }

    private struct RawStatsContainer {
        var watchTime = 0
        var movieCount = 0
        var movieCompleted = 0
        var tvCount = 0
        var tvCompleted = 0
        var epWatched = 0
        var loved = 0
        var liked = 0
        var disliked = 0
    }

    private struct TasteMapsContainer {
        var genreTaste: [String: CategoryStats] = [:]
        var networkTaste: [String: CategoryStats] = [:]
        var actorTaste: [String: CategoryStats] = [:]
        var creatorTaste: [String: CategoryStats] = [:]
        var languageTaste: [String: CategoryStats] = [:]
    }

    private func processBatch(_ items: [MediaItem], stats: inout RawStatsContainer, taste: inout TasteMapsContainer) {
        for item in items {
            let isCompleted = item.stateValue == "Completed"
            let tasteValue = item.tasteValue

            // Taste counts
            switch tasteValue {
            case "Love": stats.loved += 1
            case "Like": stats.liked += 1
            case "Dislike": stats.disliked += 1
            default: break
            }

            // Helper for taste stats
            let updateTaste: (inout [String: CategoryStats], String, String?) -> Void = { map, key, pURL in
                var s = map[key, default: CategoryStats()]
                s.total += 1
                if tasteValue == "Love" {
                    s.loved += 1
                } else if tasteValue == "Like" {
                    s.liked += 1
                } else if tasteValue == "Dislike" {
                    s.disliked += 1
                }
                if let pURL = pURL { s.profileURL = pURL }
                map[key] = s
            }

            // Stats per type
            if item.type == .movie {
                stats.movieCount += 1
                if isCompleted {
                    stats.movieCompleted += 1
                }
                stats.watchTime += item.cachedRuntime ?? 0

                for c in item.cachedCreators {
                    updateTaste(&taste.creatorTaste, c, nil)
                }
            } else if item.type == .tvShow {
                stats.tvCount += 1
                if isCompleted { stats.tvCompleted += 1 }
                
                stats.watchTime += item.cachedRuntime ?? 0

                for c in item.cachedCreators {
                    updateTaste(&taste.creatorTaste, c, nil)
                }
            }

            // Common traits (Volume & Quality)
            if item.stateValue != "Wishlist" || tasteValue != "None" {
                for g in item.cachedGenres {
                    updateTaste(&taste.genreTaste, g, nil)
                }
                if let n = item.cachedNetwork {
                    updateTaste(&taste.networkTaste, n, nil)
                }
                if let lang = item.cachedLanguage {
                    updateTaste(&taste.languageTaste, lang, nil)
                }

                for actor in item.displayCast.prefix(8) {
                    updateTaste(&taste.actorTaste, actor.name, actor.profileURL)
                }
            }
        }
    }

    private func finalizeStats(stats: RawStatsContainer, taste: TasteMapsContainer) async -> LibraryStats {
        // 1. Process Genre DNA
        let genreDNAMap = taste.genreTaste.map { name, stats in
            (name, stats.affinity(cutoff: 5))
        }
        let genreDNA = genreDNAMap
            .filter { $0.1 >= 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(8)

        // 2. Process Taste-based Rankings
        let mapTaste: ([String: CategoryStats]) -> [(String, Double)] = { statsMap in
            let affinityPairs = statsMap.map { ($0.key, $0.value.affinity(cutoff: 5)) }
            return affinityPairs
                .filter { $0.1 >= 0 }
                .sorted { $0.1 > $1.1 }
                .prefix(10)
                .map { $0 }
        }

        // 3. Visual Stats Resolution
        let actorAffinityPairs = taste.actorTaste.map { name, val in (name, val) }
        let topActors = actorAffinityPairs
            .filter { $0.1.affinity(cutoff: 5) >= 0 }
            .sorted { $0.1.affinity(cutoff: 5) > $1.1.affinity(cutoff: 5) }
            .prefix(10)

        let visualActors = await resolvePeopleImages(people: topActors.map { PersonInput(name: $0.0, stats: $0.1) })
        
        let creatorAffinityPairs = taste.creatorTaste.map { name, val in (name, val) }
        let topCreators = creatorAffinityPairs
            .filter { $0.1.affinity(cutoff: 5) >= 0 }
            .sorted { $0.1.affinity(cutoff: 5) > $1.1.affinity(cutoff: 5) }
            .prefix(10)

        let visualCreators = await resolvePeopleImages(people: topCreators.map { PersonInput(name: $0.0, stats: $0.1) })

        let languageRankings = mapTaste(taste.languageTaste).map {
            (LanguageUtils.languageName(for: $0.0), $0.1)
        }

        return LibraryStats(
            totalWatchTimeMinutes: stats.watchTime,
            totalMovies: stats.movieCount,
            completedMovies: stats.movieCompleted,
            totalTVShows: stats.tvCount,
            completedTVShows: stats.tvCompleted,
            totalEpisodesWatched: stats.epWatched,
            genreDNA: Array(genreDNA),
            topRatedActors: visualActors,
            topRatedCreators: visualCreators,
            topRatedGenres: mapTaste(taste.genreTaste),
            topRatedNetworks: mapTaste(taste.networkTaste),
            topRatedLanguages: languageRankings,
            lovedCount: stats.loved,
            likedCount: stats.liked,
            dislikedCount: stats.disliked
        )
    }

    // Move CategoryStats inside scope helper if needed, or pass fields
    private func resolvePeopleImages(people: [PersonInput]) async -> [VisualPersonStat] {
        var results: [VisualPersonStat] = []

        // Phase 5 Logic Fix: Throttle concurrent API calls to prevent 429 Rate Limiting
        let chunkSize = 5
        for i in stride(from: 0, to: people.count, by: chunkSize) {
            let end = min(i + chunkSize, people.count)
            let chunk = people[i..<end]

            await withTaskGroup(of: VisualPersonStat.self) { group in
                for input in chunk {
                    group.addTask {
                        let image = await self.resolvePersonImage(for: input.name, currentURL: input.stats.profileURL)
                        return VisualPersonStat(
                            name: input.name,
                            profileURL: image,
                            score: input.stats.affinity(cutoff: 5),
                            count: input.stats.total
                        )
                    }
                }

                for await stat in group {
                    results.append(stat)
                }
            }
        }

        return results.sorted { $0.score > $1.score }
    }
    private func resolvePersonImage(for name: String, currentURL: String?) async -> String? {
        if let current = currentURL { return current }

        // 1. Check local Cache Entity
        let cacheDescriptor = FetchDescriptor<PersonImageEntity>(
            predicate: #Predicate { $0.name == name })
        if let items = try? modelContext.fetch(cacheDescriptor), let cached = items.first {
            return cached.profileURL
        }

        // 2. On-Demand API Search
        if let path = try? await APIClient.shared.searchPerson(query: name) {
            let fullURL = APIClient.tmdbImageURL(path: path, size: "w185") ?? ""
            
            // Final check to prevent double-insert race condition
            if let items = try? modelContext.fetch(cacheDescriptor), let existing = items.first {
                return existing.profileURL
            }
            
            let newEntity = PersonImageEntity(name: name, profileURL: fullURL)
            modelContext.insert(newEntity)
            try? modelContext.save()
            return fullURL
        }

        return nil
    }
}
