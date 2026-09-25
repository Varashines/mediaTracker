import XCTest
import SwiftData
@testable import MediaTracker

final class WatchActivityResolverTests: MTTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            TVEpisode.self, WatchCycle.self, WatchEvent.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    func testLatestWatchDateUsesEpisodeTimestampInsteadOfInteractionDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let watchedAt = now.addingTimeInterval(-2 * .days7)

        let show = MediaItem(id: "tv_50", title: "Show", overview: "", type: .tvShow)
        show.stateValue = MediaState.activeRaw
        show.lastInteractionDate = now
        let details = TVShowDetails(tmdbID: 50)
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 50)
        let episode = TVEpisode(
            episodeNumber: 1,
            seasonNumber: 1,
            name: "Episode",
            overview: "",
            isWatched: true,
            showID: 50
        )
        episode.watchedDate = watchedAt
        season.episodes.append(episode)
        details.seasons.append(season)
        show.tvShowDetails = details
        context.insert(show)
        context.insert(details)
        context.insert(season)
        context.insert(episode)

        let movieWatchedAt = now.addingTimeInterval(-3 * .days7)
        let movie = MediaItem(id: "movie_50", title: "Movie", overview: "", type: .movie)
        movie.stateValue = MediaState.completedRaw
        movie.lastInteractionDate = now
        movie.lastStateChangeDate = movieWatchedAt
        context.insert(movie)
        try context.save()

        let dates = WatchActivityResolver.latestWatchDates(for: [show, movie], context: context)

        XCTAssertEqual(dates[show.id], watchedAt)
        XCTAssertEqual(dates[movie.id], movieWatchedAt)
    }

    @MainActor
    func testCandidatesSortByActualWatchDateInsteadOfInteractionDate() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()

        let older = MediaItem(id: "movie_1", title: "Older", overview: "", type: .movie)
        older.stateValue = MediaState.completedRaw
        older.lastInteractionDate = now
        older.lastStateChangeDate = now.addingTimeInterval(-2 * .days7)
        context.insert(older)

        let newer = MediaItem(id: "movie_2", title: "Newer", overview: "", type: .movie)
        newer.stateValue = MediaState.completedRaw
        newer.lastInteractionDate = .distantPast
        newer.lastStateChangeDate = now.addingTimeInterval(-3600)
        context.insert(newer)
        try context.save()

        let candidates = WatchActivityResolver.candidates(type: .movie, context: context)

        XCTAssertEqual(candidates.map(\.id), [newer.persistentModelID, older.persistentModelID])
    }

    @MainActor
    func testCandidatesFetchAllBatchesBeforeSorting() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        for index in 0..<501 {
            let item = MediaItem(id: "movie_batch_\(index)", title: "Movie \(index)", overview: "", type: .movie)
            item.stateValue = MediaState.completedRaw
            item.lastStateChangeDate = now.addingTimeInterval(Double(index))
            context.insert(item)
        }
        try context.save()

        let candidates = WatchActivityResolver.candidates(type: .movie, context: context)

        XCTAssertEqual(candidates.count, 501)
        let newest = try context.fetch(FetchDescriptor<MediaItem>(predicate: #Predicate {
            $0.id == "movie_batch_500"
        })).first
        XCTAssertEqual(candidates.first?.id, newest?.persistentModelID)
    }

    @MainActor
    func testRecentItemsIgnoreVoidedAndUnwatchedHistory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()

        let watched = MediaItem(id: "tv_1", title: "Watched", overview: "", type: .tvShow)
        watched.stateValue = MediaState.activeRaw
        context.insert(watched)
        context.insert(WatchEvent(
            cycleID: UUID(),
            mediaID: watched.id,
            episodeID: "tv_1_1_1",
            watchedAt: now.addingTimeInterval(-3600),
            deduplicationKey: "watched"
        ))

        let voided = MediaItem(id: "tv_2", title: "Voided", overview: "", type: .tvShow)
        voided.stateValue = MediaState.activeRaw
        context.insert(voided)
        let voidedEvent = WatchEvent(
            cycleID: UUID(),
            mediaID: voided.id,
            episodeID: "tv_2_1_1",
            watchedAt: now.addingTimeInterval(-1800),
            deduplicationKey: "voided"
        )
        voidedEvent.voidedAt = now
        context.insert(voidedEvent)

        let unwatched = MediaItem(id: "tv_3", title: "Unwatched", overview: "", type: .tvShow)
        unwatched.stateValue = MediaState.activeRaw
        unwatched.lastInteractionDate = now
        context.insert(unwatched)

        let deleted = MediaItem(id: "tv_deleted", title: "Deleted", overview: "", type: .tvShow)
        deleted.stateValue = MediaState.activeRaw
        deleted.isSoftDeleted = true
        context.insert(deleted)
        context.insert(WatchEvent(
            cycleID: UUID(),
            mediaID: deleted.id,
            episodeID: "tv_deleted_1_1",
            watchedAt: now,
            deduplicationKey: "deleted"
        ))

        let old = MediaItem(id: "tv_4", title: "Old Watch", overview: "", type: .tvShow)
        old.stateValue = MediaState.activeRaw
        old.lastInteractionDate = now
        context.insert(old)
        context.insert(WatchEvent(
            cycleID: UUID(),
            mediaID: old.id,
            episodeID: "tv_4_1_1",
            watchedAt: now.addingTimeInterval(-8 * .days7),
            deduplicationKey: "old"
        ))
        try context.save()

        let ids = WatchActivityResolver.recentItemIDs(
            type: .tvShow,
            cutoff: now.addingTimeInterval(-.days7),
            limit: 10,
            context: context
        )

        XCTAssertEqual(ids, [watched.persistentModelID])
    }

    @MainActor
    func testRecentItemsUseLatestWatchedEpisodeAcrossSeasons() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = Date()
        let older = now.addingTimeInterval(-2 * .days7)
        let newer = now.addingTimeInterval(-3600)

        let show = MediaItem(id: "tv_60", title: "Show", overview: "", type: .tvShow)
        show.stateValue = MediaState.activeRaw
        let details = TVShowDetails(tmdbID: 60)
        let season1 = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 60)
        let season2 = TVSeason(seasonNumber: 2, name: "Season 2", episodeCount: 1, showID: 60)
        let episode1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "One", overview: "", isWatched: true, showID: 60)
        episode1.watchedDate = older
        let episode2 = TVEpisode(episodeNumber: 1, seasonNumber: 2, name: "Two", overview: "", isWatched: true, showID: 60)
        episode2.watchedDate = newer
        season1.episodes.append(episode1)
        season2.episodes.append(episode2)
        details.seasons.append(season1)
        details.seasons.append(season2)
        show.tvShowDetails = details
        context.insert(show)
        context.insert(details)
        context.insert(season1)
        context.insert(season2)
        context.insert(episode1)
        context.insert(episode2)
        try context.save()

        let date = WatchActivityResolver.latestWatchDate(for: show, context: context)

        XCTAssertEqual(date, newer)
    }
}
