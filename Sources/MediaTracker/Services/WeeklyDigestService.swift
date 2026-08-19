import Foundation
import SwiftData

/// Summary of what was watched in the last 7 days.
struct WeeklyDigest: Sendable {
    let shows: Int
    let movies: Int
    /// The 2–3 shows with the most watched episodes this week (titles).
    let topShows: [String]
    /// Start of the 7-day window (inclusive).
    let weekStart: Date

    static let empty = WeeklyDigest(shows: 0, movies: 0, topShows: [], weekStart: Date())
}

@ModelActor
actor WeeklyDigestService {
    nonisolated static func shared(modelContainer: ModelContainer) -> WeeklyDigestService {
        WeeklyDigestService(modelContainer: modelContainer)
    }

    /// Counts shows + movies watched in the 7 days ending at `date` (inclusive).
    /// Same conventions as YearInReviewService: season 0 (specials) excluded.
    func digest(endingAt date: Date = Date()) -> WeeklyDigest {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -6, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else {
            return .empty
        }

        // 1. TV episodes watched in the window, grouped by show.
        var episodeDescriptor = FetchDescriptor<TVEpisode>(
            predicate: #Predicate { $0.isWatched && $0.seasonNumber > 0 && $0.watchedDate != nil && $0.watchedDate! >= start && $0.watchedDate! < end }
        )
        // Include every predicate field in the partial fetch. SwiftData on the
        // GitHub runner can otherwise evaluate predicates against unfetched
        // defaults and incorrectly return an empty result set.
        episodeDescriptor.propertiesToFetch = [
            \.isWatched, \.seasonNumber, \.watchedDate, \.showID
        ]
        let watchedEpisodes = (try? modelContext.fetch(episodeDescriptor)) ?? []

        var episodeCounts: [Int: Int] = [:]
        for episode in watchedEpisodes {
            if let showID = episode.showID {
                episodeCounts[showID, default: 0] += 1
            }
        }
        let shows = episodeCounts.count

        // 2. Movies completed in the window.
        var movieDescriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.typeValue == "Movie" && $0.stateValue == "Completed" && $0.lastStateChangeDate != nil && $0.lastStateChangeDate! >= start && $0.lastStateChangeDate! < end }
        )
        // Keep the predicate fields available across SwiftData runtime versions.
        movieDescriptor.propertiesToFetch = [
            \.id, \.typeValue, \.stateValue, \.lastStateChangeDate
        ]
        let movies = (try? modelContext.fetch(movieDescriptor))?.count ?? 0

        // 3. Top shows by episode count (resolve titles).
        let topShowIDs = episodeCounts.sorted { $0.value > $1.value }.prefix(3).map(\.key)
        var topShows: [String] = []
        if !topShowIDs.isEmpty {
            var itemDescriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.isSoftDeleted == false })
            itemDescriptor.propertiesToFetch = [\.id, \.title]
            let allItems = (try? modelContext.fetch(itemDescriptor)) ?? []
            let idSet = Set(topShowIDs)
            let titlesByID = allItems.reduce(into: [Int: String]()) { map, item in
                let tmdbString = item.id.split(separator: "_").last.map(String.init) ?? ""
                if let showID = Int(tmdbString), idSet.contains(showID) {
                    map[showID] = item.title
                }
            }
            topShows = topShowIDs.compactMap { titlesByID[$0] }
        }

        return WeeklyDigest(shows: shows, movies: movies, topShows: topShows, weekStart: start)
    }
}
