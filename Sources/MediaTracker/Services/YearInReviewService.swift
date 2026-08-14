import Foundation
import SwiftData

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
    let releasedMovies: [MediaThumbnailMetadata]
    let releasedTVShows: [MediaThumbnailMetadata]
    let topGenres: [(name: String, score: Double)]
    let topNetworks: [(name: String, count: Int)]
    let topActors: [ScoredPerson]
    let totalMinutes: Int
    let totalEpisodes: Int
    let totalMovies: Int
    let totalDaysWatched: Int
    let longestStreak: Int
    let busiestDay: (day: Date, minutes: Int)?
    /// Items whose release date is unknown (excluded from the 2026 sections).
    let unknownReleaseCount: Int

    func monthStats(for month: Date) -> (movies: Int, episodes: Int, minutes: Int) {
        let calendar = Calendar.current
        var movies = 0
        var episodes = 0
        var minutes = 0
        for (day, act) in activityByDay {
            if calendar.isDate(day, equalTo: month, toGranularity: .month) {
                movies += act.movies
                episodes += act.episodes
                minutes += act.minutes
            }
        }
        return (movies, episodes, minutes)
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
        case "Loved": return 0
        case "Liked": return 1
        case "Disliked": return 3
        default: return 2
        }
    }

    static func empty(year: Int) -> YearInReview {
        YearInReview(
            year: year,
            activityByDay: [:],
            titlesByDay: [:],
            releasedMovies: [],
            releasedTVShows: [],
            topGenres: [],
            topNetworks: [],
            topActors: [],
            totalMinutes: 0,
            totalEpisodes: 0,
            totalMovies: 0,
            totalDaysWatched: 0,
            longestStreak: 0,
            busiestDay: nil,
            unknownReleaseCount: 0
        )
    }
}

@ModelActor
actor YearInReviewService {
    nonisolated static func shared(modelContainer: ModelContainer) -> YearInReviewService {
        YearInReviewService(modelContainer: modelContainer)
    }

    private func accumulateTaste(
        _ item: MediaItem,
        into genreTaste: inout [String: CategoryStats],
        _ networkCounts: inout [String: Int],
        _ actorTaste: inout [String: CategoryStats],
        aliasMap: [String: String]
    ) {
        let titleWeight = TasteMath.titleWeight(for: item)
        TasteMath.accumulateGenres(&genreTaste, genres: item.cachedGenres, taste: item.tasteValue, weight: titleWeight)
        TasteMath.accumulateTopBilledCast(&actorTaste, cast: item.displayCast, taste: item.tasteValue, limit: 5, weight: titleWeight)
        if let rawNetwork = item.cachedNetwork {
            for network in rawNetwork.commaSeparatedValues {
                let groupedName = aliasMap[network.lowercased()] ?? network
                networkCounts[groupedName, default: 0] += 1
            }
        }
    }

    func compute(year: Int) async -> YearInReview {
        let calendar = Calendar.current
        guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
              let end = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else {
            return .empty(year: year)
        }

        // 1. TV episodes watched within the year (drives per-day activity + TV "watched" ids).
        //    Season 0 (specials) are excluded, matching the app's progress logic.
        var episodeDescriptor = FetchDescriptor<TVEpisode>(
            predicate: #Predicate { $0.isWatched && $0.seasonNumber > 0 && $0.watchedDate != nil && $0.watchedDate! >= start && $0.watchedDate! < end }
        )
        episodeDescriptor.propertiesToFetch = [\.watchedDate, \.runtime, \.showID, \.seasonNumber]
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
        var movieDescriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.typeValue == "Movie" && $0.stateValue == "Completed" && $0.lastStateChangeDate != nil && $0.lastStateChangeDate! >= start && $0.lastStateChangeDate! < end }
        )
        movieDescriptor.propertiesToFetch = [\.id, \.title, \.typeValue, \.cachedRuntime, \.lastStateChangeDate, \.tasteValue, \.posterURL, \.customPosterURL, \.cachedGenres, \.cachedNetwork, \.storedCast]
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

        // 3. Titles released in the target year AND watched by the user.
        var itemDescriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.isSoftDeleted == false })
        itemDescriptor.propertiesToFetch = MediaItem.thumbnailPropertiesWithCast
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

        var releasedMovies: [MediaThumbnailMetadata] = []
        var releasedTVShows: [MediaThumbnailMetadata] = []
        var unknownReleaseCount = 0

        for item in allItems {
            guard let releaseDate = item.releaseDate else {
                unknownReleaseCount += 1
                continue
            }
            guard releaseDate >= start && releaseDate < end else { continue }

            let isWatchedByMe: Bool
            if item.typeValue == "Movie" {
                isWatchedByMe = item.stateValue == "Completed"
            } else {
                let tmdbString = item.id.split(separator: "_").last.map(String.init) ?? ""
                guard let tmdbID = Int(tmdbString) else { continue }
                isWatchedByMe = watchedShowIDs.contains(tmdbID)
            }
            guard isWatchedByMe else { continue }

            let metadata = MediaThumbnailMetadata(item: item)
            if item.typeValue == "Movie" {
                releasedMovies.append(metadata)
            } else {
                releasedTVShows.append(metadata)
            }
        }

        // Taste over everything watched this year (movies completed + TV with
        // watched episodes in the year). No affinity cutoff — single titles count.
        var genreTaste: [String: CategoryStats] = [:]
        var networkCounts: [String: Int] = [:]
        var actorTaste: [String: CategoryStats] = [:]
        let watchedTVItems = itemByShowID.filter { watchedShowIDs.contains($0.key) }.values
        for item in watchedTVItems {
            accumulateTaste(item, into: &genreTaste, &networkCounts, &actorTaste, aliasMap: aliasMap)
        }
        for movie in completedMovies {
            accumulateTaste(movie, into: &genreTaste, &networkCounts, &actorTaste, aliasMap: aliasMap)
        }

        releasedMovies.sort { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }
        releasedTVShows.sort { ($0.releaseDate ?? .distantPast) > ($1.releaseDate ?? .distantPast) }

        let topGenres = genreTaste.compactMap { name, val -> (String, Double, Int)? in
            let score = val.affinity(cutoff: 1)
            guard score > 0 else { return nil }
            return (name, score, val.total)
        }.sorted { TasteMath.compareByAffinityCountName(($0.1, $0.2, $0.0), ($1.1, $1.2, $1.0)) }.prefix(8).map { ($0.0, $0.1) }

        let topActors = actorTaste.compactMap { name, val -> ScoredPerson? in
            let score = val.affinity(cutoff: 1)
            guard score > 0 else { return nil }
            return ScoredPerson(id: name, name: name, score: score, count: val.total, profileURL: val.profileURL)
        }.sorted { TasteMath.compareByAffinityCountName(($0.score, $0.count, $0.name), ($1.score, $1.count, $1.name)) }.prefix(6)

        let topNetworks = networkCounts.sorted {
            $0.1 == $1.1 ? $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending : $0.1 > $1.1
        }.prefix(8).map { ($0.0, $0.1) }

        // 4. Streaks & totals derived from per-day activity.
        let sortedDays = activity.keys.sorted()
        var longestStreak = 0
        var currentStreak = 0
        var previousDay: Date?
        for day in sortedDays {
            if let previous = previousDay,
               let next = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(day, inSameDayAs: next) {
                currentStreak += 1
            } else {
                currentStreak = 1
            }
            longestStreak = max(longestStreak, currentStreak)
            previousDay = day
        }

        let busiestDay = activity.max { $0.value.minutes < $1.value.minutes }.map { ($0.key, $0.value.minutes) }

        return YearInReview(
            year: year,
            activityByDay: activity,
            titlesByDay: titlesByDay,
            releasedMovies: releasedMovies,
            releasedTVShows: releasedTVShows,
            topGenres: topGenres,
            topNetworks: topNetworks,
            topActors: Array(topActors),
            totalMinutes: activity.values.reduce(0) { $0 + $1.minutes },
            totalEpisodes: totalEpisodes,
            totalMovies: totalMovies,
            totalDaysWatched: activity.count,
            longestStreak: longestStreak,
            busiestDay: busiestDay,
            unknownReleaseCount: unknownReleaseCount
        )
    }
}
