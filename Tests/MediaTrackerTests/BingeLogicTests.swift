import XCTest
import SwiftData
@testable import MediaTracker

final class BingeLogicTests: XCTestCase {
    // Current date in session is Wednesday, 29 April 2026
    let nowString = "2026-04-29"

    @MainActor
    func testBingeDropLogic() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 1. Setup a show with multiple episodes on the same day (Future Binge Drop)
        let item = MediaItem(id: "future_binge_drop", title: "Future Binge Drop Show", overview: "Overview", type: .tvShow)
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 101)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 101)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // Released in 3 days
        let airDate = "2026-05-02"
        for i in 1...10 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: airDate, showID: 101)
            if i == 1 { ep.isWatched = true } // Mark first watched to avoid Premiere priority
            ep.season = season
            season.episodes.append(ep)
            context.insert(ep)
        }
        
        item.syncCachedProperties()
        
        XCTAssertTrue(item.storedIsBingeDrop, "Should be detected as Binge Drop (Future)")
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE DROP")
    }

    @MainActor
    func testSeriesPremiereLogic() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "series_prem", title: "Series Premiere Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 102)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 8, showID: 102)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // Next ep is S1 E1, airing in 5 days (beyond SOON window)
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "", airDate: "2026-05-04", showID: 102)
        ep1.season = season
        season.episodes.append(ep1)
        
        item.syncCachedProperties()
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "SERIES PREMIERE")
    }

    @MainActor
    func testSeasonPremiereLogic() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "season_prem", title: "Season Premiere Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 103)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season2 = TVSeason(seasonNumber: 2, name: "Season 2", episodeCount: 10, showID: 103)
        season2.tvShowDetails = tvDetails
        tvDetails.seasons.append(season2)
        
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 2, name: "New Start", overview: "", airDate: "2026-05-10", showID: 103)
        ep1.season = season2
        season2.episodes.append(ep1)
        
        item.syncCachedProperties()
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "SEASON PREMIERE")
    }

    @MainActor
    func testPastPremiereDoesNotShowBadge() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "past_prem", title: "Past Premiere Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 104)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season1 = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 104)
        season1.tvShowDetails = tvDetails
        tvDetails.seasons.append(season1)
        
        // Yesterday's date
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayString = DateFormatter.tmdb.string(from: yesterday)
        
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "", airDate: yesterdayString, showID: 104)
        ep1.season = season1
        season1.episodes.append(ep1)
        
        item.syncCachedProperties()
        
        XCTAssertNotEqual(item.storedSmartBadgeLabel, "SERIES PREMIERE")
        // It should be "STREAMING" since it's recently aired (yesterday)
        XCTAssertEqual(item.storedSmartBadgeLabel, "STREAMING")
    }

    @MainActor
    func testSoonBadgeLogic() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Movie releasing tomorrow
        let movie = MediaItem(id: "soon_movie", title: "Soon Movie", overview: "", type: .movie)
        movie.releaseDate = Calendar.current.date(byAdding: .day, value: 1, to: Date())
        context.insert(movie)
        
        movie.syncCachedProperties()
        XCTAssertEqual(movie.storedSmartBadgeLabel, "SOON")
        
        // Show with regular episode (not premiere) airing tomorrow
        let show = MediaItem(id: "soon_show", title: "Soon Show", overview: "", type: .tvShow)
        context.insert(show)
        let tvDetails = TVShowDetails(tmdbID: 104)
        tvDetails.item = show
        show.tvShowDetails = tvDetails
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 104)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        let ep2 = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Ep 2", overview: "", airDate: DateFormatter.tmdb.string(from: Calendar.current.date(byAdding: .day, value: 1, to: Date())!))
        ep2.season = season
        season.episodes.append(ep2)
        
        show.syncCachedProperties()
        XCTAssertEqual(show.storedSmartBadgeLabel, "SOON")
    }

    @MainActor
    func testFinaleBadgeLogicFuture() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "future_finale", title: "Future Finale Show", overview: "", type: .tvShow)
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 105)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 105)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // Finale airing in 10 days
        let airDate = "2026-05-10"
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "The End", overview: "", airDate: airDate)
        ep1.season = season
        season.episodes.append(ep1)
        
        item.syncCachedProperties()
        
        // Even if E1, it's the last episode of the season, so it could be SEASON PREMIERE or FINALE.
        // In my current logic, episodeNumber == 1 (SEASON PREMIERE) comes BEFORE FINALE.
        // Let's test with E8 of 8.
        
        let item2 = MediaItem(id: "future_finale_8", title: "Future Finale 8", overview: "", type: .tvShow)
        context.insert(item2)
        let tvDetails2 = TVShowDetails(tmdbID: 106)
        tvDetails2.item = item2
        item2.tvShowDetails = tvDetails2
        let season2 = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 8, showID: 106)
        season2.tvShowDetails = tvDetails2
        tvDetails2.seasons.append(season2)
        
        for i in 1...7 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.isWatched = true
            ep.season = season2
            season2.episodes.append(ep)
        }
        
        let ep8 = TVEpisode(episodeNumber: 8, seasonNumber: 1, name: "Finale", overview: "", airDate: "2026-05-10")
        ep8.season = season2
        season2.episodes.append(ep8)
        
        item2.syncCachedProperties()
        XCTAssertEqual(item2.storedSmartBadgeLabel, "FINALE", "Finale should show even if in the future")
    }
    
    @MainActor
    func testPeckingOrder() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Show that is both SOON and SEASON PREMIERE
        let item = MediaItem(id: "multi_badge", title: "Multi Badge Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 106)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        let season = TVSeason(seasonNumber: 2, name: "Season 2", episodeCount: 10, showID: 106)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 2, name: "Ep 1", overview: "", airDate: DateFormatter.tmdb.string(from: tomorrow))
        ep1.season = season
        season.episodes.append(ep1)
        
        item.syncCachedProperties()
        
        // SEASON PREMIERE (1/2) > BINGE DROP (3)
        XCTAssertEqual(item.storedSmartBadgeLabel, "SEASON PREMIERE")
    }
}

extension DateFormatter {
    static let tmdb: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
