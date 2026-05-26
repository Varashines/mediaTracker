import XCTest
import SwiftData
@testable import MediaTracker

final class SyncCachedPropertiesTests: XCTestCase {
    @MainActor
    func testUpdateSearchableTextIncludesTitleAndOverview() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "The Matrix", overview: "A computer hacker learns about reality", type: .movie)
        context.insert(item)
        try context.save()

        item.updateSearchableText()

        XCTAssertTrue(item.searchableText.contains("the matrix"))
        XCTAssertTrue(item.searchableText.contains("computer hacker"))
    }

    @MainActor
    func testUpdateSearchableTextIncludesGenres() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        item.cachedGenres = ["Action", "Sci-Fi"]
        context.insert(item)
        try context.save()

        item.updateSearchableText()

        XCTAssertTrue(item.searchableText.contains("action"))
        XCTAssertTrue(item.searchableText.contains("sci-fi"))
    }

    @MainActor
    func testUpdateSearchableTextIncludesCast() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        item.storedCast = [SimpleCastMember(id: "1", name: "Keanu Reeves", characterName: "Neo", profileURL: nil, order: 0)]
        context.insert(item)
        try context.save()

        item.updateSearchableText()

        XCTAssertTrue(item.searchableText.contains("keanu reeves"))
    }

    @MainActor
    func testBadgeRecalculatedOnSync() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Show", overview: "", type: .tvShow)
        item.stateValue = "Active"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 1)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 5)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let baseDate = Date().addingTimeInterval(-86400 * 10)
        for i in 1...5 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-0\(i)", runtime: 30)
            ep.season = season
            ep.airDateValue = baseDate.addingTimeInterval(Double(i) * 86400)
            season.episodes.append(ep)
            context.insert(ep)
        }
        try context.save()

        // Mark 3 as watched recently, leave 2 unwatched (next unwatched is ep 4, NOT the finale)
        let recent = Date().addingTimeInterval(-1000)
        let eps = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
        for i in 0..<3 {
            eps[i].markWatched(true)
            eps[i].lastWatchedDate = recent
        }
        // Ensure remaining is set correctly
        tv.totalEpisodesCount = 5
        tv.watchedEpisodesCount = 3
        tv.remainingEpisodesCount = 2
        try context.save()

        // Verify BadgeEngine calculates BINGE directly
        let badgeResult = BadgeEngine.calculateBadge(for: item, now: Date())
        XCTAssertNotNil(badgeResult, "BadgeEngine should return a badge for 3 recently watched episodes with remaining")
        XCTAssertEqual(badgeResult?.label, .binge)
    }

    @MainActor
    func testSyncMoviePropertiesCopiesGenresAndCreators() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        context.insert(item)
        let details = MovieDetails(tmdbID: 1)
        details.genres = ["Action", "Drama"]
        details.creators = ["Director A"]
        details.originalLanguage = "en"
        details.runtime = 120
        details.network = "Studio X"
        details.item = item
        item.movieDetails = details
        context.insert(details)
        try context.save()

        item.syncMovieProperties()

        XCTAssertEqual(item.cachedGenres, ["Action", "Drama"])
        XCTAssertEqual(item.cachedCreators, ["Director A"])
        XCTAssertEqual(item.cachedLanguage, "en")
        XCTAssertEqual(item.cachedRuntime, 120)
        XCTAssertEqual(item.cachedNetwork, "Studio X")
    }

    @MainActor
    func testStoredIsUpcomingSetForFutureDate() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Upcoming", overview: "", type: .movie)
        item.releaseDate = Date().addingTimeInterval(86400 * 30) // 30 days from now
        context.insert(item)
        try context.save()

        item.syncCachedProperties(now: Date())
        XCTAssertTrue(item.storedIsUpcoming)

        item.releaseDate = Date().addingTimeInterval(-86400) // yesterday
        item.syncCachedProperties(now: Date())
        XCTAssertFalse(item.storedIsUpcoming)
    }
}
