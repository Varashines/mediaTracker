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
            let score = Double(3 * loved + 1 * liked - 2 * disliked) / Double(3 * ratedCount)
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

        var watchTime = 0
        var movieCount = 0
        var movieCompleted = 0
        var tvCount = 0
        var tvCompleted = 0
        var epWatched = 0

        var loved = 0
        var liked = 0
        var disliked = 0

        var genreTaste: [String: CategoryStats] = [:]
        var networkTaste: [String: CategoryStats] = [:]
        var actorTaste: [String: CategoryStats] = [:]
        var creatorTaste: [String: CategoryStats] = [:]
        var languageTaste: [String: CategoryStats] = [:]

        // Phase 5 Optimization: Batched Processing to prevent memory exhaustion
        let batchSize = 500
        var offset = 0
        
        while true {
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            
            guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { break }
            
            for item in items {
                let isCompleted = item.stateValue == "Completed"
                let tasteValue = item.tasteValue

                // Taste counts
                switch tasteValue {
                case "Love": loved += 1
                case "Like": liked += 1
                case "Dislike": disliked += 1
                default: break
                }

                // Helper for taste stats
                let updateTaste: (inout CategoryStats, String?) -> Void = { stats, pURL in
                    stats.total += 1
                    if tasteValue == "Love" {
                        stats.loved += 1
                    } else if tasteValue == "Like" {
                        stats.liked += 1
                    } else if tasteValue == "Dislike" {
                        stats.disliked += 1
                    }
                    if let pURL = pURL { stats.profileURL = pURL }
                }

                // Stats per type
                if item.type == .movie {
                    movieCount += 1
                    if isCompleted {
                        movieCompleted += 1
                        watchTime += item.movieDetails?.runtime ?? 0
                    }

                    if let creators = item.movieDetails?.creators {
                        for c in creators {
                            updateTaste(&creatorTaste[c, default: CategoryStats()], nil)
                        }
                    }
                } else if item.type == .tvShow {
                    tvCount += 1
                    if isCompleted { tvCompleted += 1 }

                    if let tvDetails = item.tvShowDetails {
                        let watchedEpisodes = tvDetails.seasons.flatMap { $0.episodes }.filter {
                            $0.isWatched
                        }
                        epWatched += watchedEpisodes.count
                        watchTime += watchedEpisodes.reduce(0) { $0 + ($1.runtime ?? 0) }

                        for c in tvDetails.creators {
                            updateTaste(&creatorTaste[c, default: CategoryStats()], nil)
                        }
                    }
                }

                // Common traits (Volume & Quality)
                if item.stateValue != "Wishlist" || tasteValue != "None" {
                    for g in item.cachedGenres {
                        updateTaste(&genreTaste[g, default: CategoryStats()], nil)
                    }
                    if let n = item.cachedNetwork {
                        updateTaste(&networkTaste[n, default: CategoryStats()], nil)
                    }
                    if let lang = item.cachedLanguage {
                        updateTaste(&languageTaste[lang, default: CategoryStats()], nil)
                    }

                    for actor in item.displayCast.prefix(8) {
                        updateTaste(&actorTaste[actor.name, default: CategoryStats()], actor.profileURL)
                    }
                }
            }
            
            offset += batchSize
            modelContext.processPendingChanges()
        }

        // 1. Process Genre DNA (Taste-based, strict 5 rated title bar)
        let genreDNA = genreTaste.map { name, stats in
            (name, stats.affinity(cutoff: 5))
        }
        .filter { $0.1 >= 0 }
        .sorted { $0.1 > $1.1 }
        .prefix(8)

        // 2. Process Taste-based Rankings (Strict 5 Rated Title Bar)
        let mapTaste: ([String: CategoryStats]) -> [(String, Double)] = { stats in
            stats.map { ($0.key, $0.value.affinity(cutoff: 5)) }
                .filter { $0.1 >= 0 }
                .sorted { $0.1 > $1.1 }
                .prefix(10)
                .map { $0 }
        }

        // 3. Visual Stats Resolution (Top Actors/Creators)
        let topActors = actorTaste.map { name, val in (name, val) }
            .filter { $0.1.affinity(cutoff: 5) >= 0 }
            .sorted { $0.1.affinity(cutoff: 5) > $1.1.affinity(cutoff: 5) }
            .prefix(10)

        let visualActors = await resolvePeopleImages(people: topActors.map { PersonInput(name: $0.0, stats: $0.1) })
        
        let topCreators = creatorTaste.map { name, val in (name, val) }
            .filter { $0.1.affinity(cutoff: 5) >= 0 }
            .sorted { $0.1.affinity(cutoff: 5) > $1.1.affinity(cutoff: 5) }
            .prefix(10)

        let visualCreators = await resolvePeopleImages(people: topCreators.map { PersonInput(name: $0.0, stats: $0.1) })

        let result = LibraryStats(
            totalWatchTimeMinutes: watchTime,
            totalMovies: movieCount,
            completedMovies: movieCompleted,
            totalTVShows: tvCount,
            completedTVShows: tvCompleted,
            totalEpisodesWatched: epWatched,
            genreDNA: Array(genreDNA),
            topRatedActors: visualActors,
            topRatedCreators: visualCreators,
            topRatedGenres: mapTaste(genreTaste),
            topRatedNetworks: mapTaste(networkTaste),
            topRatedLanguages: mapTaste(languageTaste).map {
                (LanguageUtils.languageName(for: $0.0), $0.1)
            },
            lovedCount: loved,
            likedCount: liked,
            dislikedCount: disliked
        )

        await MainActor.run {
            Self.cachedStats = result
            Self.lastCalculation = Date()
        }

        return result
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
