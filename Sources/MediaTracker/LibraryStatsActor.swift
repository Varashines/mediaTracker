import Foundation
import SwiftData

struct LibraryStats: Sendable {
    let totalWatchTimeMinutes: Int
    
    let totalMovies: Int
    let completedMovies: Int
    
    let totalTVShows: Int
    let completedTVShows: Int
    
    let totalEpisodesWatched: Int
    
    // Volume-based (Top 5)
    let topGenres: [(name: String, count: Int)]
    let topNetworks: [(name: String, count: Int)]
    let topActors: [(name: String, count: Int)]
    let topCreators: [(name: String, count: Int)]
    
    // Taste-based (Top 5)
    let topRatedGenres: [(name: String, score: Double)]
    let topRatedNetworks: [(name: String, score: Double)]
    let topRatedActors: [(name: String, score: Double)]
    let topRatedCreators: [(name: String, score: Double)]
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
        topGenres: [],
        topNetworks: [],
        topActors: [],
        topCreators: [],
        topRatedGenres: [],
        topRatedNetworks: [],
        topRatedActors: [],
        topRatedCreators: [],
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
    private let cacheTTL: TimeInterval = 3600 // 1 hour

    func fetchStats() async -> LibraryStats {
        // Check cache
        let (cached, last) = await MainActor.run { (Self.cachedStats, Self.lastCalculation) }
        if let cached = cached, let last = last, Date().timeIntervalSince(last) < cacheTTL {
            return cached
        }

        let descriptor = FetchDescriptor<MediaItem>()
        guard let allItems = try? modelContext.fetch(descriptor) else {
            return .empty
        }

        var watchTime = 0
        var movieCount = 0
        var movieCompleted = 0
        var tvCount = 0
        var tvCompleted = 0
        var epWatched = 0
        
        var genreCounts: [String: Int] = [:]
        var networkCounts: [String: Int] = [:]
        var actorCounts: [String: Int] = [:]
        var creatorCounts: [String: Int] = [:]
        
        var loved = 0
        var liked = 0
        var disliked = 0
        
        // Taste Affinity Helpers
        struct CategoryStats {
            var loved = 0
            var liked = 0
            var disliked = 0
            var total = 0
            func affinity(cutoff: Int = 3) -> Double {
                guard total >= cutoff else { return -1.0 } // Mark as ineligible
                return Double(3 * loved + 1 * liked - 2 * disliked) / Double(3 * total)
            }
        }
        
        var genreTaste: [String: CategoryStats] = [:]
        var networkTaste: [String: CategoryStats] = [:]
        var actorTaste: [String: CategoryStats] = [:]
        var creatorTaste: [String: CategoryStats] = [:]
        var languageTaste: [String: CategoryStats] = [:]

        for item in allItems {
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
            let updateTaste: (inout CategoryStats) -> Void = { stats in
                stats.total += 1
                if tasteValue == "Love" { stats.loved += 1 }
                else if tasteValue == "Like" { stats.liked += 1 }
                else if tasteValue == "Dislike" { stats.disliked += 1 }
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
                        creatorCounts[c, default: 0] += 1
                        if tasteValue != "None" { updateTaste(&creatorTaste[c, default: CategoryStats()]) }
                    }
                }
            } else if item.type == .tvShow {
                tvCount += 1
                if isCompleted { tvCompleted += 1 }
                
                if let tvDetails = item.tvShowDetails {
                    let watchedEpisodes = tvDetails.seasons.flatMap { $0.episodes }.filter { $0.isWatched }
                    epWatched += watchedEpisodes.count
                    watchTime += watchedEpisodes.reduce(0) { $0 + ($1.runtime ?? 0) }
                    
                    for c in tvDetails.creators { 
                        creatorCounts[c, default: 0] += 1 
                        if tasteValue != "None" { updateTaste(&creatorTaste[c, default: CategoryStats()]) }
                    }
                }
            }
            
            // Common traits
            if item.stateValue != "Wishlist" {
                for g in item.cachedGenres {
                    genreCounts[g, default: 0] += 1
                    if tasteValue != "None" { updateTaste(&genreTaste[g, default: CategoryStats()]) }
                }
                if let n = item.cachedNetwork {
                    networkCounts[n, default: 0] += 1
                    if tasteValue != "None" { updateTaste(&networkTaste[n, default: CategoryStats()]) }
                }
                if let lang = item.cachedLanguage {
                    if tasteValue != "None" { updateTaste(&languageTaste[lang, default: CategoryStats()]) }
                }
                
                for actor in item.displayCast.prefix(5) {
                    actorCounts[actor.name, default: 0] += 1
                    if tasteValue != "None" { updateTaste(&actorTaste[actor.name, default: CategoryStats()]) }
                }
            }
        }

        // Processing Volume-based (Top 5)
        let sortedGenres = genreCounts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }.prefix(5)
        let sortedNetworks = networkCounts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }.prefix(5)
        let sortedActors = actorCounts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }.prefix(5)
        let sortedCreators = creatorCounts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }.prefix(5)
        
        // Processing Taste-based (Top 5)
        let mapTaste: ([String: CategoryStats]) -> [(String, Double)] = { stats in
            stats.map { ($0.key, $0.value.affinity()) }
                .filter { $0.1 >= 0 } // Filter out those below cutoff
                .sorted { $0.1 > $1.1 }
                .prefix(5)
                .map { $0 }
        }

        let result = LibraryStats(
            totalWatchTimeMinutes: watchTime,
            totalMovies: movieCount,
            completedMovies: movieCompleted,
            totalTVShows: tvCount,
            completedTVShows: tvCompleted,
            totalEpisodesWatched: epWatched,
            topGenres: Array(sortedGenres),
            topNetworks: Array(sortedNetworks),
            topActors: Array(sortedActors),
            topCreators: Array(sortedCreators),
            topRatedGenres: mapTaste(genreTaste),
            topRatedNetworks: mapTaste(networkTaste),
            topRatedActors: mapTaste(actorTaste),
            topRatedCreators: mapTaste(creatorTaste),
            topRatedLanguages: mapTaste(languageTaste).map { (LanguageUtils.languageName(for: $0.0), $0.1) },
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
}
