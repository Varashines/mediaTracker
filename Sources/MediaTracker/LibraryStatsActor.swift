import Foundation
import SwiftData

struct VisualPersonStat: Sendable {
    let name: String
    let profileURL: String?
    let score: Double
    let count: Int
}

struct WatchTimePoint: Sendable, Identifiable {
    let id = UUID()
    let date: Date
    let minutes: Int
}

struct DecadeDistributionPoint: Sendable, Identifiable {
    let id = UUID()
    let decade: String
    let count: Int
}

struct BarcodeSlice: Sendable, Identifiable {
    let id: String
    let title: String
    let tasteValue: String
    let themeColorHex: String?
}

struct CompletedItemRepresentation: Sendable, Identifiable {
    let id: String
    let title: String
    let posterURL: String?
    let themeColorHex: String?
    let completedDate: Date
    let typeValue: String
}

struct CreatorCollaboration: Sendable, Identifiable {
    let id: String
    let actorName: String
    let creatorName: String
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
    let topRatedStudios: [(name: String, score: Double)]
    let topRatedLanguages: [(name: String, score: Double)]

    let lovedCount: Int
    let likedCount: Int
    let dislikedCount: Int
    
    let watchTimeHistory: [WatchTimePoint]
    let decadeDistribution: [DecadeDistributionPoint]
    
    let collaborations: [CreatorCollaboration]
    let completedItems: [CompletedItemRepresentation]
    let barcodeData: [BarcodeSlice]

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
        topRatedStudios: [],
        topRatedLanguages: [],
        lovedCount: 0,
        likedCount: 0,
        dislikedCount: 0,
        watchTimeHistory: [],
        decadeDistribution: [],
        collaborations: [],
        completedItems: [],
        barcodeData: []
    )
}

@ModelActor
actor LibraryStatsActor {
    @MainActor private static var cachedStats: LibraryStats?
    @MainActor private static var lastCalculation: Date?
    private let cacheTTL: TimeInterval = 3600  // 1 hour
    
    @MainActor
    static func clearCache() {
        cachedStats = nil
        lastCalculation = nil
    }

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
        let precomputedScore: Double
    }

    func fetchStats() async -> LibraryStats {
        // Check cache
        let (cached, last) = await MainActor.run { (Self.cachedStats, Self.lastCalculation) }
        if let cached = cached, let last = last, Date().timeIntervalSince(last) < cacheTTL {
            return cached
        }

        var statsContainer = RawStatsContainer()
        var tasteMaps = TasteMapsContainer()

        // Compute hidden set once before batch loop
        let hiddenStudios = UserDefaults.standard.string(forKey: UserDefaultsKeys.hiddenStudios.rawValue) ?? ""
        let hiddenSet = Set(hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty }.map { $0.lowercased() })

        // Phase 5 Optimization: Batched Processing to prevent memory exhaustion
        let batchSize = 500
        var offset = 0
        
        while true {
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            
            guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { break }
            
            processBatch(items, stats: &statsContainer, taste: &tasteMaps, hiddenSet: hiddenSet)
            
            offset += batchSize
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
        var history: [Date: Int] = [:]
        var decadeCounts: [String: Int] = [:]
        var completedItemsList: [CompletedItemRepresentation] = []
        var collaborationsCount: [String: Int] = [:]
        var barcodeData: [BarcodeSlice] = []
    }

    private struct TasteMapsContainer {
        var genreTaste: [String: CategoryStats] = [:]
        var networkTaste: [String: CategoryStats] = [:]
        var studioTaste: [String: CategoryStats] = [:]
        var actorTaste: [String: CategoryStats] = [:]
        var creatorTaste: [String: CategoryStats] = [:]
        var languageTaste: [String: CategoryStats] = [:]
    }

    private func updateTaste(_ map: inout [String: CategoryStats], _ key: String, _ tasteValue: String, _ pURL: String? = nil) {
        var s = map[key, default: CategoryStats()]
        s.total += 1
        if let taste = TasteValue(rawValue: tasteValue) {
            switch taste {
            case .love: s.loved += 1
            case .like: s.liked += 1
            case .dislike: s.disliked += 1
            case .none: break
            }
        }
        if let pURL = pURL { s.profileURL = pURL }
        map[key] = s
    }

    private func processBatch(_ items: [MediaItem], stats: inout RawStatsContainer, taste: inout TasteMapsContainer, hiddenSet: Set<String>) {
        let calendar = Calendar.current
        for item in items {
            let isCompleted = item.stateValue == "Completed"
            let tasteValue = item.tasteValue

            stats.barcodeData.append(BarcodeSlice(
                id: item.id,
                title: item.title,
                tasteValue: tasteValue,
                themeColorHex: item.themeColorHex
            ))

            // Taste counts
            if let taste = TasteValue(rawValue: tasteValue) {
                switch taste {
                case .love: stats.loved += 1
                case .like: stats.liked += 1
                case .dislike: stats.disliked += 1
                case .none: break
                }
            }

            // Stats per type
            if item.type == .movie {
                stats.movieCount += 1
                if isCompleted {
                    stats.movieCompleted += 1
                    let runtime = item.cachedRuntime ?? 0
                    stats.watchTime += runtime
                    
                    if let date = item.lastInteractionDate {
                        let day = calendar.startOfDay(for: date)
                        stats.history[day, default: 0] += runtime
                    }
                }

                for c in item.cachedCreators {
                    updateTaste(&taste.creatorTaste, c, tasteValue)
                }
            } else if item.type == .tvShow {
                stats.tvCount += 1
                if isCompleted { stats.tvCompleted += 1 }
                
                let runtime = item.cachedRuntime ?? 0
                stats.watchTime += runtime
                stats.epWatched += item.cachedWatchedEpisodeCount ?? 0
                
                // Per-episode history using watchedDate for accurate daily breakdown
                if let tv = item.tvShowDetails {
                    for season in tv.seasons where !season.isDeleted && season.modelContext != nil {
                        for ep in season.episodes where ep.isWatched && !ep.isDeleted && ep.modelContext != nil {
                            if let date = ep.watchedDate, let epRuntime = ep.runtime, epRuntime > 0 {
                                let day = calendar.startOfDay(for: date)
                                stats.history[day, default: 0] += epRuntime
                            }
                        }
                    }
                }

                for c in item.cachedCreators {
                    updateTaste(&taste.creatorTaste, c, tasteValue)
                }
            }

            // Common traits (Volume & Quality)
            if item.stateValue != "Wishlist" || tasteValue != TasteValue.none.rawValue {
                for g in item.cachedGenres {
                    updateTaste(&taste.genreTaste, g, tasteValue)
                }
                if let rawNetwork = item.cachedNetwork {
                    let networks = rawNetwork.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    for n in networks where !n.isEmpty {
                        if !hiddenSet.contains(n.lowercased()) {
                            if item.type == .movie {
                                updateTaste(&taste.studioTaste, n, tasteValue)
                            } else {
                                updateTaste(&taste.networkTaste, n, tasteValue)
                            }
                        }
                    }
                }
                if let lang = item.cachedLanguage {
                    updateTaste(&taste.languageTaste, lang, tasteValue)
                }

                let limit = item.type == .movie ? 5 : 10
                for actor in item.displayCast.prefix(limit) {
                    updateTaste(&taste.actorTaste, actor.name, tasteValue, actor.profileURL)
                }
            }

            if let releaseDate = item.releaseDate {
                let year = calendar.component(.year, from: releaseDate)
                let decadeStart = (year / 10) * 10
                let decadeName = "\(decadeStart)s"
                stats.decadeCounts[decadeName, default: 0] += 1
            }

            if isCompleted {
                let date = item.lastStateChangeDate ?? item.lastInteractionDate ?? Date()
                stats.completedItemsList.append(CompletedItemRepresentation(
                    id: item.id,
                    title: item.title,
                    posterURL: item.posterURL,
                    themeColorHex: item.themeColorHex,
                    completedDate: date,
                    typeValue: item.typeValue
                ))
            }

            for creator in item.cachedCreators {
                for actor in item.displayCast.prefix(10) {
                    let key = "\(actor.name)|\(creator)"
                    stats.collaborationsCount[key, default: 0] += 1
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
            .prefix(10)

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
        let actorWithScore: [(String, CategoryStats, Double)] = taste.actorTaste.compactMap { name, val in
            let score = val.affinity(cutoff: 5)
            return score >= 0 ? (name, val, score) : nil
        }
        let topActors = actorWithScore.sorted { $0.2 > $1.2 }.prefix(10)

        let visualActors = await resolvePeopleImages(people: topActors.map { PersonInput(name: $0.0, stats: $0.1, precomputedScore: $0.2) }, cutoff: 5)
        
        let creatorWithScore: [(String, CategoryStats, Double)] = taste.creatorTaste.compactMap { name, val in
            let score = val.affinity(cutoff: 3)
            return score >= 0 ? (name, val, score) : nil
        }
        let topCreators = creatorWithScore.sorted { $0.2 > $1.2 }.prefix(10)

        let visualCreators = await resolvePeopleImages(people: topCreators.map { PersonInput(name: $0.0, stats: $0.1, precomputedScore: $0.2) }, cutoff: 3)

        let languageRankings = mapTaste(taste.languageTaste).map {
            (LanguageUtils.languageName(for: $0.0), $0.1)
        }
        
        let history = stats.history.map { WatchTimePoint(date: $0.key, minutes: $0.value) }
            .sorted { $0.date < $1.date }

        let decadeDistribution = stats.decadeCounts.map { DecadeDistributionPoint(decade: $0.key, count: $0.value) }
            .sorted { $0.decade < $1.decade }

        let topActorNames = Set(visualActors.map { $0.name })
        let topCreatorNames = Set(visualCreators.map { $0.name })
        let collaborations = stats.collaborationsCount.compactMap { key, count -> CreatorCollaboration? in
            let parts = key.components(separatedBy: "|")
            guard parts.count == 2 else { return nil }
            let actor = parts[0]
            let creator = parts[1]
            guard topActorNames.contains(actor) && topCreatorNames.contains(creator) else { return nil }
            return CreatorCollaboration(id: key, actorName: actor, creatorName: creator, count: count)
        }

        let completedItems = Array(stats.completedItemsList
            .sorted { $0.completedDate > $1.completedDate }
            .prefix(100))

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
            topRatedStudios: mapTaste(taste.studioTaste),
            topRatedLanguages: languageRankings,
            lovedCount: stats.loved,
            likedCount: stats.liked,
            dislikedCount: stats.disliked,
            watchTimeHistory: history,
            decadeDistribution: decadeDistribution,
            collaborations: collaborations,
            completedItems: completedItems,
            barcodeData: stats.barcodeData
        )
    }

    // Move CategoryStats inside scope helper if needed, or pass fields
    private func resolvePeopleImages(people: [PersonInput], cutoff: Int) async -> [VisualPersonStat] {
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
                            score: input.precomputedScore,
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
