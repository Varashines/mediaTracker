import Foundation
import SwiftData

/// In-memory snapshot cache for the year review (mirrors `ScopedStatsCache`).
/// Revisits are instant; invalidated on any media state change. Holds a strong
/// reference to the container so its `ObjectIdentifier` can't be reused by a
/// deallocated container (which would return a stale review for another store).
@MainActor
final class YearReviewCache {
    static let shared = YearReviewCache()
    private init() {}

    private struct CacheKey: Hashable {
        let containerID: ObjectIdentifier
        let year: Int
    }

    private var cache: [CacheKey: (container: ModelContainer, review: YearInReview)] = [:]

    func review(containerID: ObjectIdentifier, year: Int) -> YearInReview? {
        cache[CacheKey(containerID: containerID, year: year)]?.review
    }

    func setReview(_ review: YearInReview, containerID: ObjectIdentifier, year: Int, container: ModelContainer) {
        let key = CacheKey(containerID: containerID, year: year)
        cache[key] = (container, review)
    }

    func invalidate() {
        cache.removeAll()
    }
}

/// Per-day watch activity for a single day of the review year.
struct YearDayActivity: Sendable, Equatable {
    var minutes: Int
    var episodes: Int
    var movies: Int

    static let zero = YearDayActivity(minutes: 0, episodes: 0, movies: 0)
}

/// A single title watched on a given day (movie completion or TV show with
/// watched episodes that day).
struct YearWatchedTitle: Sendable, Identifiable {
    let id: PersistentIdentifier
    let title: String
    let posterURL: String?
    let type: MediaType
    let tasteValue: String
    /// Episodes watched that day (0 for movies).
    let episodeCount: Int
}

/// Snapshot of a single year's review: watch-activity heatmap data, the set of
/// titles released that year and watched by the user, and taste derived ONLY
/// from that released-that-year set (not general library taste).
struct YearInReview: Sendable {
    let year: Int
    let activityByDay: [Date: YearDayActivity]
    /// Titles watched per calendar day (for day drill-down + month collages).
    let titlesByDay: [Date: [YearWatchedTitle]]
    let topGenres: [(name: String, score: Double, count: Int)]
    let topNetworks: [(name: String, count: Int, logoPath: String?)]
    let topLanguages: [(name: String, score: Double, count: Int)]
    let topActors: [ScoredPerson]
    let totalMinutes: Int
    let totalEpisodes: Int
    let totalMovies: Int
    let totalSeries: Int
    let totalDaysWatched: Int
    let busiestDay: (day: Date, minutes: Int)?

    func monthStats(for month: Date) -> (movies: Int, series: Int, minutes: Int) {
        let calendar = Calendar.current
        var movies = 0
        var series = 0
        var minutes = 0
        var seenSeries = Set<PersistentIdentifier>()
        for (day, act) in activityByDay {
            if calendar.isDate(day, equalTo: month, toGranularity: .month) {
                movies += act.movies
                minutes += act.minutes
            }
        }
        for title in monthTitles(for: month) {
            if title.type == .tvShow, seenSeries.insert(title.id).inserted {
                series += 1
            }
        }
        return (movies, series, minutes)
    }

    func monthTitles(for month: Date) -> [YearWatchedTitle] {
        let calendar = Calendar.current
        var seen = Set<PersistentIdentifier>()
        var result: [YearWatchedTitle] = []
        let sortedDays = titlesByDay.keys
            .filter { calendar.isDate($0, equalTo: month, toGranularity: .month) }
            .sorted()

        for day in sortedDays {
            for title in titlesByDay[day] ?? [] {
                if seen.insert(title.id).inserted {
                    result.append(title)
                }
            }
        }

        return result.sorted {
            let r0 = tasteRank($0.tasteValue)
            let r1 = tasteRank($1.tasteValue)
            if r0 != r1 { return r0 < r1 }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func tasteRank(_ taste: String) -> Int {
        switch taste {
        case "Love", "Loved": return 0
        case "Like", "Liked": return 1
        case "Dislike", "Disliked": return 3
        default: return 2
        }
    }

    static func empty(year: Int) -> YearInReview {
        YearInReview(
            year: year,
            activityByDay: [:],
            titlesByDay: [:],
            topGenres: [],
            topNetworks: [],
            topLanguages: [],
            topActors: [],
            totalMinutes: 0,
            totalEpisodes: 0,
            totalMovies: 0,
            totalSeries: 0,
            totalDaysWatched: 0,
            busiestDay: nil
        )
    }
}

@ModelActor
actor YearInReviewService {
    nonisolated static func shared(modelContainer: ModelContainer) -> YearInReviewService {
        YearInReviewService(modelContainer: modelContainer)
    }

    func compute(year: Int) async -> YearInReview {
        // Fast path: return the in-memory snapshot if one exists for this store.
        let containerID = ObjectIdentifier(modelContext.container)
        if let cached = await YearReviewCache.shared.review(containerID: containerID, year: year) {
            return cached
        }

        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return .empty(year: year)
        }

        // 1. TV episodes watched within the year (drives per-day activity + TV "watched" ids).
        //    Season 0 (specials) are excluded, matching the app's progress logic.
        let episodeDescriptor = FetchDescriptor<TVEpisode>(
            predicate: #Predicate { $0.isWatched && $0.seasonNumber > 0 && $0.watchedDate != nil && $0.watchedDate! >= start && $0.watchedDate! < end }
        )
        let watchedEpisodes = (try? modelContext.fetch(episodeDescriptor)) ?? []

        var activity: [Date: YearDayActivity] = [:]
        var watchedShowIDs = Set<Int>()
        var showDayCounts: [Int: [Date: Int]] = [:]
        var totalEpisodes = 0
        for episode in watchedEpisodes {
            guard let watchedDate = episode.watchedDate else { continue }
            let day = calendar.startOfDay(for: watchedDate)
            var slot = activity[day] ?? .zero
            slot.episodes += 1
            slot.minutes += episode.runtime ?? 0
            activity[day] = slot
            totalEpisodes += 1
            if let showID = episode.showID {
                watchedShowIDs.insert(showID)
                showDayCounts[showID, default: [:]][day, default: 0] += 1
            }
        }

        // 2. Movies completed within the year.
        let movieDescriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.typeValue == "Movie" && $0.stateValue == "Completed" && $0.lastStateChangeDate != nil && $0.lastStateChangeDate! >= start && $0.lastStateChangeDate! < end }
        )
        let completedMovies = (try? modelContext.fetch(movieDescriptor)) ?? []

        var titlesByDay: [Date: [YearWatchedTitle]] = [:]
        var totalMovies = 0
        for movie in completedMovies {
            guard let completedDate = movie.lastStateChangeDate else { continue }
            let day = calendar.startOfDay(for: completedDate)
            var slot = activity[day] ?? .zero
            slot.movies += 1
            slot.minutes += movie.cachedRuntime ?? 0
            activity[day] = slot
            totalMovies += 1
            titlesByDay[day, default: []].append(YearWatchedTitle(
                id: movie.persistentModelID,
                title: movie.title,
                posterURL: movie.effectivePosterURL,
                type: .movie,
                tasteValue: movie.tasteValue,
                episodeCount: 0
            ))
        }

        // 3. TV show metadata for titlesByDay + taste. Use full model fetches
        // here because partial SwiftData fetches are not reliable across the
        // supported macOS/Xcode runtimes for custom array-backed properties.
        var itemDescriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.isSoftDeleted == false })
        itemDescriptor.fetchLimit = 2000
        let allItems = (try? modelContext.fetch(itemDescriptor)) ?? []

        let aliasEntities = (try? modelContext.fetch(FetchDescriptor<StudioAliasEntity>())) ?? []
        let aliasMap = DiscoverySyncService.buildSourceToTargetMap(from: aliasEntities)

        var itemByShowID: [Int: MediaItem] = [:]
        for item in allItems where item.typeValue == "TV Show" {
            let tmdbString = item.id.split(separator: "_").last.map(String.init) ?? ""
            if let showID = Int(tmdbString) { itemByShowID[showID] = item }
        }
        for (showID, dayCounts) in showDayCounts {
            guard let item = itemByShowID[showID] else { continue }
            for (day, count) in dayCounts {
                titlesByDay[day, default: []].append(YearWatchedTitle(
                    id: item.persistentModelID,
                    title: item.title,
                    posterURL: item.effectivePosterURL,
                    type: .tvShow,
                    tasteValue: item.tasteValue,
                    episodeCount: count
                ))
            }
        }

        // Taste over everything watched this year (movies completed + TV with
        // watched episodes in the year). No affinity cutoff — single titles count.
        var genreTaste: [String: CategoryStats] = [:]
        var networkCounts: [String: Int] = [:]
        var networkLogos: [String: String] = [:]
        var languageTaste: [String: CategoryStats] = [:]
        var actorTaste: [String: CategoryStats] = [:]
        let watchedTVItems = itemByShowID.filter { watchedShowIDs.contains($0.key) }.values
        for item in watchedTVItems {
            accumulateTaste(item, into: &genreTaste, &networkCounts, &networkLogos, &languageTaste, &actorTaste, aliasMap: aliasMap)
        }
        for movie in completedMovies {
            accumulateTaste(movie, into: &genreTaste, &networkCounts, &networkLogos, &languageTaste, &actorTaste, aliasMap: aliasMap)
        }

        let topGenres = genreTaste.compactMap { name, val -> (String, Double, Int)? in
            let score = val.affinity(cutoff: 1)
            guard score > 0 else { return nil }
            return (name, score, val.total)
        }.sorted { TasteMath.compareByAffinityCountName(($0.1, $0.2, $0.0), ($1.1, $1.2, $1.0)) }.prefix(8).map { ($0.0, $0.1, $0.2) }

        let topActors = actorTaste.compactMap { name, val -> ScoredPerson? in
            let score = val.affinity(cutoff: 1)
            guard score > 0 else { return nil }
            return ScoredPerson(id: name, name: name, score: score, count: val.total, profileURL: val.profileURL)
        }.sorted { TasteMath.compareByAffinityCountName(($0.score, $0.count, $0.name), ($1.score, $1.count, $1.name)) }.prefix(6)

        let topNetworks = networkCounts.sorted {
            $0.1 == $1.1 ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending : $0.1 > $1.1
        }.prefix(8).map { ($0.0, $0.1, networkLogos[$0.0]) }

        let topLanguages = languageTaste.compactMap { code, val -> (String, Double, Int)? in
            let score = val.affinity(cutoff: 1)
            guard score > 0 else { return nil }
            return (LanguageUtils.languageName(for: code), score, val.total)
        }.sorted { TasteMath.compareByAffinityCountName(($0.1, $0.2, $0.0), ($1.1, $1.2, $1.0)) }.prefix(8).map { ($0.0, $0.1, $0.2) }

        let busiestDay = activity.max { $0.value.minutes < $1.value.minutes }.map { ($0.key, $0.value.minutes) }

        let result = YearInReview(
            year: year,
            activityByDay: activity,
            titlesByDay: titlesByDay,
            topGenres: topGenres,
            topNetworks: topNetworks,
            topLanguages: topLanguages,
            topActors: Array(topActors),
            totalMinutes: activity.values.reduce(0) { $0 + $1.minutes },
            totalEpisodes: totalEpisodes,
            totalMovies: totalMovies,
            totalSeries: watchedTVItems.count,
            totalDaysWatched: activity.count,
            busiestDay: busiestDay
        )
        await YearReviewCache.shared.setReview(result, containerID: containerID, year: year, container: modelContext.container)
        return result
    }

    private func accumulateTaste(
        _ item: MediaItem,
        into genreTaste: inout [String: CategoryStats],
        _ networkCounts: inout [String: Int],
        _ networkLogos: inout [String: String],
        _ languageTaste: inout [String: CategoryStats],
        _ actorTaste: inout [String: CategoryStats],
        aliasMap: [String: String]
    ) {
        let titleWeight = TasteMath.titleWeight(for: item)
        TasteMath.accumulateGenres(&genreTaste, genres: item.cachedGenres, taste: item.tasteValue, weight: titleWeight)
        if let language = item.cachedLanguage, !language.isEmpty {
            TasteMath.updateTaste(&languageTaste, language, item.tasteValue, weight: titleWeight)
        }
        TasteMath.accumulateTopBilledCast(&actorTaste, cast: item.displayCast, taste: item.tasteValue, limit: 5, weight: titleWeight)
        if let rawNetwork = item.cachedNetwork {
            let logoPaths = item.cachedNetworkLogoPath?.commaSeparatedValues ?? []
            for (index, network) in rawNetwork.commaSeparatedValues.enumerated() {
                let groupedName = aliasMap[network.lowercased()] ?? network
                networkCounts[groupedName, default: 0] += 1
                if networkLogos[groupedName] == nil, index < logoPaths.count, !logoPaths[index].isEmpty {
                    networkLogos[groupedName] = logoPaths[index]
                }
            }
        }
    }
}
