import Foundation
import SwiftData

struct VisualPersonStat: Sendable, Codable {
    let name: String
    let profileURL: String?
    let score: Double
    let count: Int
}

struct WatchTimePoint: Sendable, Identifiable, Codable {
    let id: UUID
    let date: Date
    let minutes: Int

    init(id: UUID = UUID(), date: Date, minutes: Int) {
        self.id = id
        self.date = date
        self.minutes = minutes
    }
}

struct DecadeDistributionPoint: Sendable, Identifiable, Codable {
    let id: UUID
    let decade: String
    let count: Int

    init(id: UUID = UUID(), decade: String, count: Int) {
        self.id = id
        self.decade = decade
        self.count = count
    }
}

struct BarcodeSlice: Sendable, Identifiable, Codable {
    let id: String
    let title: String
    let tasteValue: String
    let themeColorHex: String?
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
    let topRatedNetworks: [(name: String, score: Double)]
    let topRatedStudios: [(name: String, score: Double)]
    let topRatedLanguages: [(name: String, score: Double)]

    let lovedCount: Int
    let likedCount: Int
    let dislikedCount: Int
    let unratedCount: Int

    let watchTimeHistory: [WatchTimePoint]
    let decadeDistribution: [DecadeDistributionPoint]

    let barcodeData: [BarcodeSlice]

    // Passport personality
    let currentStreak: Int
    let longestStreak: Int
    let ratingPersonality: String
    let archetype: String
    let movieWatchTimeMinutes: Int
    let tvWatchTimeMinutes: Int
    let watchVelocityMinutesPerDay: Int
    let favoriteEra: String?
    let memberSince: Date?

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
        topRatedNetworks: [],
        topRatedStudios: [],
        topRatedLanguages: [],
        lovedCount: 0,
        likedCount: 0,
        dislikedCount: 0,
        unratedCount: 0,
        watchTimeHistory: [],
        decadeDistribution: [],
        barcodeData: [],
        currentStreak: 0,
        longestStreak: 0,
        ratingPersonality: "",
        archetype: "",
        movieWatchTimeMinutes: 0,
        tvWatchTimeMinutes: 0,
        watchVelocityMinutesPerDay: 0,
        favoriteEra: nil,
        memberSince: nil
    )
}

struct CodableLibraryStats: Codable {
    struct NamePercentage: Codable {
        let name: String
        let percentage: Double
    }
    struct NameScore: Codable {
        let name: String
        let score: Double
    }

    let totalWatchTimeMinutes: Int
    let totalMovies: Int
    let completedMovies: Int
    let totalTVShows: Int
    let completedTVShows: Int
    let totalEpisodesWatched: Int

    let genreDNA: [NamePercentage]
    let topRatedActors: [VisualPersonStat]
    let topRatedCreators: [VisualPersonStat]
    let topRatedNetworks: [NameScore]
    let topRatedStudios: [NameScore]
    let topRatedLanguages: [NameScore]

    let lovedCount: Int
    let likedCount: Int
    let dislikedCount: Int
    let unratedCount: Int

    let watchTimeHistory: [WatchTimePoint]
    let decadeDistribution: [DecadeDistributionPoint]
    let barcodeData: [BarcodeSlice]

    let currentStreak: Int
    let longestStreak: Int
    let ratingPersonality: String
    let archetype: String
    let movieWatchTimeMinutes: Int
    let tvWatchTimeMinutes: Int
    let watchVelocityMinutesPerDay: Int
    let favoriteEra: String?
    let memberSince: Date?

    init(_ stats: LibraryStats) {
        self.totalWatchTimeMinutes = stats.totalWatchTimeMinutes
        self.totalMovies = stats.totalMovies
        self.completedMovies = stats.completedMovies
        self.totalTVShows = stats.totalTVShows
        self.completedTVShows = stats.completedTVShows
        self.totalEpisodesWatched = stats.totalEpisodesWatched
        self.genreDNA = stats.genreDNA.map { NamePercentage(name: $0.name, percentage: $0.percentage) }
        self.topRatedActors = stats.topRatedActors
        self.topRatedCreators = stats.topRatedCreators
        self.topRatedNetworks = stats.topRatedNetworks.map { NameScore(name: $0.name, score: $0.score) }
        self.topRatedStudios = stats.topRatedStudios.map { NameScore(name: $0.name, score: $0.score) }
        self.topRatedLanguages = stats.topRatedLanguages.map { NameScore(name: $0.name, score: $0.score) }
        self.lovedCount = stats.lovedCount
        self.likedCount = stats.likedCount
        self.dislikedCount = stats.dislikedCount
        self.unratedCount = stats.unratedCount
        self.watchTimeHistory = stats.watchTimeHistory
        self.decadeDistribution = stats.decadeDistribution
        self.barcodeData = stats.barcodeData
        self.currentStreak = stats.currentStreak
        self.longestStreak = stats.longestStreak
        self.ratingPersonality = stats.ratingPersonality
        self.archetype = stats.archetype
        self.movieWatchTimeMinutes = stats.movieWatchTimeMinutes
        self.tvWatchTimeMinutes = stats.tvWatchTimeMinutes
        self.watchVelocityMinutesPerDay = stats.watchVelocityMinutesPerDay
        self.favoriteEra = stats.favoriteEra
        self.memberSince = stats.memberSince
    }

    func toLibraryStats() -> LibraryStats {
        LibraryStats(
            totalWatchTimeMinutes: totalWatchTimeMinutes,
            totalMovies: totalMovies,
            completedMovies: completedMovies,
            totalTVShows: totalTVShows,
            completedTVShows: completedTVShows,
            totalEpisodesWatched: totalEpisodesWatched,
            genreDNA: genreDNA.map { ($0.name, $0.percentage) },
            topRatedActors: topRatedActors,
            topRatedCreators: topRatedCreators,
            topRatedNetworks: topRatedNetworks.map { ($0.name, $0.score) },
            topRatedStudios: topRatedStudios.map { ($0.name, $0.score) },
            topRatedLanguages: topRatedLanguages.map { ($0.name, $0.score) },
            lovedCount: lovedCount,
            likedCount: likedCount,
            dislikedCount: dislikedCount,
            unratedCount: unratedCount,
            watchTimeHistory: watchTimeHistory,
            decadeDistribution: decadeDistribution,
            barcodeData: barcodeData,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            ratingPersonality: ratingPersonality,
            archetype: archetype,
            movieWatchTimeMinutes: movieWatchTimeMinutes,
            tvWatchTimeMinutes: tvWatchTimeMinutes,
            watchVelocityMinutesPerDay: watchVelocityMinutesPerDay,
            favoriteEra: favoriteEra,
            memberSince: memberSince
        )
    }
}

struct CachedStatsWrapper: Codable {
    let lastCalculationDate: Date
    let stats: CodableLibraryStats
}

@ModelActor
actor LibraryStatsActor {
    @MainActor private static var cachedLightStats: LibraryStats?
    @MainActor private static var cachedFullStats: LibraryStats?
    @MainActor private static var cachedContainers: (RawStatsContainer, TasteMapsContainer)?
    @MainActor private static var lastCalculation: Date?
    private let cacheTTL: TimeInterval = 3600  // 1 hour
    
    private static func getCacheURL(full: Bool) -> URL {
        URL.applicationSupportDirectory.appendingPathComponent(full ? "LibraryStatsCache_full.json" : "LibraryStatsCache_light.json")
    }

    private static func loadPersistentStats(full: Bool, cacheTTL: TimeInterval) -> (LibraryStats, Date)? {
        let url = getCacheURL(full: full)
        guard let data = try? Data(contentsOf: url),
              let wrapper = try? JSONDecoder().decode(CachedStatsWrapper.self, from: data) else {
            return nil
        }
        if Date().timeIntervalSince(wrapper.lastCalculationDate) < cacheTTL {
            return (wrapper.stats.toLibraryStats(), wrapper.lastCalculationDate)
        }
        return nil
    }

    private static func savePersistentStats(_ stats: LibraryStats, full: Bool, date: Date) {
        let url = getCacheURL(full: full)
        let wrapper = CachedStatsWrapper(lastCalculationDate: date, stats: CodableLibraryStats(stats))
        if let data = try? JSONEncoder().encode(wrapper) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static func deletePersistentStats() {
        try? FileManager.default.removeItem(at: getCacheURL(full: true))
        try? FileManager.default.removeItem(at: getCacheURL(full: false))
    }

    @MainActor
    static func clearCache() {
        cachedLightStats = nil
        cachedFullStats = nil
        cachedContainers = nil
        lastCalculation = nil
        deletePersistentStats()
    }

    func fetchStats(includeCinephileData: Bool = true) async throws -> LibraryStats {
        try Task.checkCancellation()
        let (cached, last) = await MainActor.run {
            if includeCinephileData {
                (Self.cachedFullStats, Self.lastCalculation)
            } else {
                (Self.cachedLightStats, Self.lastCalculation)
            }
        }
        if let cached = cached, let last = last, Date().timeIntervalSince(last) < cacheTTL {
            return cached
        }

        // Try load from persistent storage
        if let (persistentStats, lastCalcDate) = Self.loadPersistentStats(full: includeCinephileData, cacheTTL: cacheTTL) {
            await MainActor.run {
                if includeCinephileData {
                    Self.cachedFullStats = persistentStats
                } else {
                    Self.cachedLightStats = persistentStats
                }
                Self.lastCalculation = lastCalcDate
            }
            return persistentStats
        }

        var statsContainer = RawStatsContainer()
        var tasteMaps = TasteMapsContainer()

        let hiddenStudios = UserDefaults.standard.string(forKey: UserDefaultsKeys.hiddenStudios.rawValue) ?? ""
        let hiddenSet = Set(hiddenStudios.components(separatedBy: ",").filter { !$0.isEmpty }.map { $0.lowercased() })

        // Single query pre-fetch of watched TV episodes to avoid N+1 traversals during stats calculations
        var tvWatchedEpisodesMap: [Int: [TVEpisode]] = [:]
        if includeCinephileData {
            let epDescriptor = FetchDescriptor<TVEpisode>(
                predicate: #Predicate<TVEpisode> { $0.isWatched }
            )
            if let watchedEpisodes = try? modelContext.fetch(epDescriptor) {
                for ep in watchedEpisodes {
                    if let showID = ep.showID {
                        tvWatchedEpisodesMap[showID, default: []].append(ep)
                    }
                }
            }
        }

        let batchSize = 500
        var offset = 0
        
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.propertiesToFetch = [
                \.id, \.title, \.releaseDate,
                \.typeValue, \.stateValue, \.tasteValue, \.themeColorHex,
                \.lastInteractionDate, \.lastStateChangeDate,
                \.cachedGenres, \.cachedCreators, \.cachedLanguage, \.cachedNetwork,
                \.cachedRuntime, \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount,
                \.storedSmartBadgeLabel, \.storedIsUpcoming, \.storedCast
            ]
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            
            guard let items = try? modelContext.fetch(descriptor), !items.isEmpty else { break }
            
            processBatch(items, stats: &statsContainer, taste: &tasteMaps, hiddenSet: hiddenSet, tvWatchedEpisodesMap: tvWatchedEpisodesMap, includeCinephileData: includeCinephileData)
            
            offset += batchSize
        }

        try Task.checkCancellation()
        let result = try await finalizeStats(stats: statsContainer, taste: tasteMaps, includeCinephileData: includeCinephileData)

        let calculationDate = Date()
        await MainActor.run {
            if includeCinephileData {
                Self.cachedFullStats = result
                Self.cachedContainers = nil  // Release intermediate containers after finalization
            } else {
                Self.cachedLightStats = result
                Self.cachedContainers = nil
            }
            Self.lastCalculation = calculationDate
        }

        Self.savePersistentStats(result, full: includeCinephileData, date: calculationDate)

        return result
    }

    func fetchCinephileData() async throws -> LibraryStats? {
        return try await fetchStats(includeCinephileData: true)
    }

    // Taste Affinity Helpers

    private struct PersonInput: Sendable {
        let name: String
        let stats: CategoryStats
        let precomputedScore: Double
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
        var unrated = 0
        var history: [Date: Int] = [:]
        var decadeCounts: [String: Int] = [:]
        var barcodeData: [BarcodeSlice] = []
        var movieWatchTime = 0
        var tvWatchTime = 0
        var interactionDates: Set<Date> = []
        var earliestDateAdded: Date?
    }

    private struct TasteMapsContainer {
        var genreTaste: [String: CategoryStats] = [:]
        var networkTaste: [String: CategoryStats] = [:]
        var studioTaste: [String: CategoryStats] = [:]
        var actorTaste: [String: CategoryStats] = [:]
        var creatorTaste: [String: CategoryStats] = [:]
        var languageTaste: [String: CategoryStats] = [:]
    }

    private func processBatch(_ items: [MediaItem], stats: inout RawStatsContainer, taste: inout TasteMapsContainer, hiddenSet: Set<String>, tvWatchedEpisodesMap: [Int: [TVEpisode]], includeCinephileData: Bool = true) {
        let calendar = Calendar.current
        for item in items {
            let isCompleted = item.stateValue == "Completed"
            let tasteValue = item.tasteValue

            if includeCinephileData && stats.barcodeData.count < 200 {
                stats.barcodeData.append(BarcodeSlice(
                    id: item.id,
                    title: item.title,
                    tasteValue: tasteValue,
                    themeColorHex: item.themeColorHex
                ))
            }

            // Taste counts
            if let taste = TasteValue(rawValue: tasteValue) {
                switch taste {
                case .love: stats.loved += 1
                case .like: stats.liked += 1
                case .dislike: stats.disliked += 1
                case .none: stats.unrated += 1
                }
            }

            // Streak & member since tracking
            if let interactionDate = item.lastInteractionDate {
                let day = calendar.startOfDay(for: interactionDate)
                stats.interactionDates.insert(day)
            }
            if let dateAdded = item.dateAdded {
                if let earliest = stats.earliestDateAdded {
                    if dateAdded < earliest {
                        stats.earliestDateAdded = dateAdded
                    }
                } else {
                    stats.earliestDateAdded = dateAdded
                }
            }

            // Stats per type
            if item.type == .movie {
                stats.movieCount += 1
                if isCompleted {
                    stats.movieCompleted += 1
                    let runtime = item.cachedRuntime ?? 0
                    stats.watchTime += runtime
                    stats.movieWatchTime += runtime
                    
                    if includeCinephileData, let date = item.lastInteractionDate {
                        let day = calendar.startOfDay(for: date)
                        stats.history[day, default: 0] += runtime
                    }
                }

                for c in item.cachedCreators {
                    TasteMath.updateTaste(&taste.creatorTaste, c, tasteValue)
                }
            } else if item.type == .tvShow {
                stats.tvCount += 1
                if isCompleted { stats.tvCompleted += 1 }
                
                let runtime = item.cachedRuntime ?? 0
                stats.watchTime += runtime
                stats.tvWatchTime += runtime
                stats.epWatched += item.cachedWatchedEpisodeCount ?? 0
                
                if includeCinephileData {
                    var hasWatchedDate = false
                    let tmdbIDString = item.id.split(separator: "_").last ?? item.id[...]
                    if let tmdbID = Int(tmdbIDString), let watchedEps = tvWatchedEpisodesMap[tmdbID] {
                        for ep in watchedEps {
                            let epRuntime = ep.runtime ?? item.cachedEpisodeRuntime ?? 0
                            if let date = ep.watchedDate, epRuntime > 0 {
                                let day = calendar.startOfDay(for: date)
                                stats.history[day, default: 0] += epRuntime
                                stats.tvWatchTime += epRuntime
                                hasWatchedDate = true
                            }
                        }
                    }
                    if !hasWatchedDate, let date = item.lastInteractionDate {
                        let runtime = item.type == .tvShow ? (item.cachedEpisodeRuntime ?? 0) : (item.cachedRuntime ?? 0)
                        if runtime > 0 {
                            let day = calendar.startOfDay(for: date)
                            stats.history[day, default: 0] += runtime
                        }
                    }
                }

                for c in item.cachedCreators {
                    TasteMath.updateTaste(&taste.creatorTaste, c, tasteValue)
                }
            }

            // Common traits (Volume & Quality)
            if item.stateValue != "Wishlist" || tasteValue != TasteValue.none.rawValue {
                for g in item.cachedGenres {
                    TasteMath.updateTaste(&taste.genreTaste, g, tasteValue)
                }
                if let rawNetwork = item.cachedNetwork {
                    let networks = rawNetwork.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    for n in networks where !n.isEmpty {
                        if !hiddenSet.contains(n.lowercased()) {
                            if item.type == .movie {
                                TasteMath.updateTaste(&taste.studioTaste, n, tasteValue)
                            } else {
                                TasteMath.updateTaste(&taste.networkTaste, n, tasteValue)
                            }
                        }
                    }
                }
                if let lang = item.cachedLanguage {
                    TasteMath.updateTaste(&taste.languageTaste, lang, tasteValue)
                }

                let limit = item.type == .movie ? 5 : 10
                for actor in item.displayCast.prefix(limit) {
                    TasteMath.updateTaste(&taste.actorTaste, actor.name, tasteValue, profileURL: actor.profileURL)
                }
            }

            if includeCinephileData, let releaseDate = item.releaseDate {
                let year = calendar.component(.year, from: releaseDate)
                let decadeStart = (year / 10) * 10
                let decadeName = "\(decadeStart)s"
                stats.decadeCounts[decadeName, default: 0] += 1
            }
        }
    }

    private func finalizeStats(stats: RawStatsContainer, taste: TasteMapsContainer, includeCinephileData: Bool = true) async throws -> LibraryStats {
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

        // 3. Visual Stats Resolution (capped at 5+5 to limit API calls)
        let actorWithScore: [(String, CategoryStats, Double)] = taste.actorTaste.compactMap { name, val in
            let score = val.affinity(cutoff: 5)
            return score >= 0 ? (name, val, score) : nil
        }
        let topActors = actorWithScore.sorted { $0.2 > $1.2 }.prefix(5)

        let visualActors = try await resolvePeopleImages(people: topActors.map { PersonInput(name: $0.0, stats: $0.1, precomputedScore: $0.2) }, cutoff: 5)

        let creatorWithScore: [(String, CategoryStats, Double)] = taste.creatorTaste.compactMap { name, val in
            let score = val.affinity(cutoff: 3)
            return score >= 0 ? (name, val, score) : nil
        }
        let topCreators = creatorWithScore.sorted { $0.2 > $1.2 }.prefix(5)

        let visualCreators = try await resolvePeopleImages(people: topCreators.map { PersonInput(name: $0.0, stats: $0.1, precomputedScore: $0.2) }, cutoff: 3)

        let languageRankings = mapTaste(taste.languageTaste).map {
            (LanguageUtils.languageName(for: $0.0), $0.1)
        }

        let history: [WatchTimePoint]
        let decadeDistribution: [DecadeDistributionPoint]

        if includeCinephileData {
            history = stats.history.map { WatchTimePoint(date: $0.key, minutes: $0.value) }
                .sorted { $0.date < $1.date }

            decadeDistribution = stats.decadeCounts.map { DecadeDistributionPoint(decade: $0.key, count: $0.value) }
                .sorted { $0.decade < $1.decade }
        } else {
            history = []
            decadeDistribution = []
        }

        // 4. Compute personality & passport stats
        let (currentStreak, longestStreak) = computeStreaks(from: stats.interactionDates)
        let ratingPersonality = computeRatingPersonality(loved: stats.loved, liked: stats.liked, disliked: stats.disliked, unrated: stats.unrated)
        let archetype = computeArchetype(
            totalMovies: stats.movieCount,
            completedMovies: stats.movieCompleted,
            totalTV: stats.tvCount,
            completedTV: stats.tvCompleted,
            loved: stats.loved,
            liked: stats.liked,
            disliked: stats.disliked,
            tvWatchTime: stats.tvWatchTime,
            totalWatchTime: stats.watchTime
        )
        let velocity = computeWatchVelocity(history: history)
        let favoriteEra = stats.decadeCounts.max { $0.value < $1.value }?.key

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
            topRatedNetworks: mapTaste(taste.networkTaste),
            topRatedStudios: mapTaste(taste.studioTaste),
            topRatedLanguages: languageRankings,
            lovedCount: stats.loved,
            likedCount: stats.liked,
            dislikedCount: stats.disliked,
            unratedCount: stats.unrated,
            watchTimeHistory: history,
            decadeDistribution: decadeDistribution,
            barcodeData: stats.barcodeData,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
            ratingPersonality: ratingPersonality,
            archetype: archetype,
            movieWatchTimeMinutes: stats.movieWatchTime,
            tvWatchTimeMinutes: stats.tvWatchTime,
            watchVelocityMinutesPerDay: velocity,
            favoriteEra: favoriteEra,
            memberSince: stats.earliestDateAdded
        )
    }

    private func computeStreaks(from dates: Set<Date>) -> (current: Int, longest: Int) {
        guard !dates.isEmpty else { return (0, 0) }
        let sorted = dates.sorted()
        let calendar = Calendar.current
        var longest = 1
        var current = 1
        var currentRun = 1
        for i in 1..<sorted.count {
            if let next = calendar.date(byAdding: .day, value: 1, to: sorted[i - 1]),
               calendar.isDate(next, inSameDayAs: sorted[i]) {
                currentRun += 1
                longest = max(longest, currentRun)
            } else {
                currentRun = 1
            }
        }
        // Check if today or yesterday is in the set for current streak
        let today = calendar.startOfDay(for: Date())
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            if dates.contains(today) {
                current = streakRunCount(from: today, dates: dates, calendar: calendar)
            } else if dates.contains(yesterday) {
                current = streakRunCount(from: yesterday, dates: dates, calendar: calendar)
            } else {
                current = 0
            }
        }
        return (current, longest)
    }

    private func streakRunCount(from date: Date, dates: Set<Date>, calendar: Calendar) -> Int {
        var count = 0
        var currentDate = date
        while dates.contains(currentDate) {
            count += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
            currentDate = prev
        }
        return count
    }

    private func computeRatingPersonality(loved: Int, liked: Int, disliked: Int, unrated: Int) -> String {
        let rated = loved + liked + disliked
        guard rated > 0 else { return "Mystery Critic" }
        let lovedPct = Double(loved) / Double(rated)
        let dislikedPct = Double(disliked) / Double(rated)
        if lovedPct > 0.55 { return "Hopeless Romantic" }
        if dislikedPct > 0.25 { return "Harsh Critic" }
        if loved > 0 && liked > 0 && disliked == 0 { return "Enthusiast" }
        return "Balanced"
    }

    private func computeArchetype(totalMovies: Int, completedMovies: Int, totalTV: Int, completedTV: Int, loved: Int, liked: Int, disliked: Int, tvWatchTime: Int, totalWatchTime: Int) -> String {
        let total = totalMovies + totalTV
        let completed = completedMovies + completedTV
        let completionRate = total > 0 ? Double(completed) / Double(total) : 0
        let rated = loved + liked + disliked
        let lovedPct = rated > 0 ? Double(loved) / Double(rated) : 0
        let tvPct = totalWatchTime > 0 ? Double(tvWatchTime) / Double(totalWatchTime) : 0

        if completionRate > 0.8 && lovedPct > 0.5 { return "The Completionist" }
        if total > 50 && completionRate < 0.5 { return "The Explorer" }
        if tvPct > 0.7 && totalTV > 20 { return "The Binger" }
        if lovedPct > 0.6 && completionRate > 0.6 { return "The Curator" }
        if total < 20 { return "The Newcomer" }
        return "The Enthusiast"
    }

    private func computeWatchVelocity(history: [WatchTimePoint]) -> Int {
        guard !history.isEmpty else { return 0 }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: today) else { return 0 }
        let recent = history.filter { $0.date >= thirtyDaysAgo }
        let totalMinutes = recent.reduce(0) { $0 + $1.minutes }
        let days = max(1, calendar.dateComponents([.day], from: thirtyDaysAgo, to: today).day ?? 30)
        return totalMinutes / days
    }

    private func resolvePeopleImages(people: [PersonInput], cutoff: Int) async throws -> [VisualPersonStat] {
        var results: [VisualPersonStat] = []

        let chunkSize = 5
        for i in stride(from: 0, to: people.count, by: chunkSize) {
            try Task.checkCancellation()
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

        let cacheDescriptor = FetchDescriptor<PersonImageEntity>(
            predicate: #Predicate { $0.name == name })
        if let items = try? modelContext.fetch(cacheDescriptor), let cached = items.first {
            return cached.profileURL
        }

        // Check local CastMember data before hitting the API
        let castDescriptor = FetchDescriptor<CastMember>(predicate: #Predicate { $0.name == name })
        if let member = try? modelContext.fetch(castDescriptor).first(where: { $0.profileURL != nil }) {
            let url = member.profileURL
            modelContext.insert(PersonImageEntity(name: name, profileURL: url))
            return url
        }

        if let path = try? await APIClient.shared.searchPerson(query: name) {
            let fullURL = APIClient.tmdbImageURL(path: path, size: "w185") ?? ""

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
