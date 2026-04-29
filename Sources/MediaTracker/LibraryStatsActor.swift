import Foundation
import SwiftData

struct LibraryStats: Sendable {
    let totalWatchTimeMinutes: Int
    
    let totalMovies: Int
    let completedMovies: Int
    
    let totalTVShows: Int
    let completedTVShows: Int
    
    let totalEpisodesWatched: Int
    
    let topGenres: [(name: String, count: Int)]
    let topNetworks: [(name: String, count: Int)]
    
    static let empty = LibraryStats(
        totalWatchTimeMinutes: 0,
        totalMovies: 0,
        completedMovies: 0,
        totalTVShows: 0,
        completedTVShows: 0,
        totalEpisodesWatched: 0,
        topGenres: [],
        topNetworks: []
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

        for item in allItems {
            let isCompleted = item.stateValue == "Completed"
            
            // Stats per type
            if item.type == .movie {
                movieCount += 1
                if isCompleted {
                    movieCompleted += 1
                    watchTime += item.movieDetails?.runtime ?? 0
                }
            } else if item.type == .tvShow {
                tvCount += 1
                if isCompleted { tvCompleted += 1 }
                
                if let tvDetails = item.tvShowDetails {
                    let watchedEpisodes = tvDetails.seasons.flatMap { $0.episodes }.filter { $0.isWatched }
                    epWatched += watchedEpisodes.count
                    watchTime += watchedEpisodes.reduce(0) { $0 + ($1.runtime ?? 0) }
                }
            }
            
            // Only count genres/networks for items in library (not just wishlist)
            if item.stateValue != "Wishlist" {
                for g in item.cachedGenres {
                    genreCounts[g, default: 0] += 1
                }
                if let n = item.cachedNetwork {
                    networkCounts[n, default: 0] += 1
                }
            }
        }

        let sortedGenres = genreCounts.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
            .prefix(15)
        
        let sortedNetworks = networkCounts.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
            .prefix(15)

        let result = LibraryStats(
            totalWatchTimeMinutes: watchTime,
            totalMovies: movieCount,
            completedMovies: movieCompleted,
            totalTVShows: tvCount,
            completedTVShows: tvCompleted,
            totalEpisodesWatched: epWatched,
            topGenres: Array(sortedGenres),
            topNetworks: Array(sortedNetworks)
        )

        await MainActor.run {
            Self.cachedStats = result
            Self.lastCalculation = Date()
        }
        
        return result
    }
}
