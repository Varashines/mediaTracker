import XCTest
import SwiftData
@testable import MediaTracker

final class BingeLogicTests: XCTestCase {
    // Reference date for all tests
    let nowString = "2026-04-29"
    var testNow: Date { DateUtils.parseDate(nowString)! }

    @MainActor
    func testBingeDropLogic() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "future_binge_drop", title: "Future Binge Drop Show", overview: "Overview", type: .tvShow)
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 101)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        context.insert(tvDetails)
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 101)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        context.insert(season)
        
        // Use same day to ensure it's close to testNow
        let airDate = "2026-04-29" 
        for i in 1...10 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: airDate, showID: 101)
            if i == 1 { ep.isWatched = true } // Mark first watched to avoid Premiere priority
            ep.season = season
            // Use parseEpisodeDate to ensure it matches the engine's parsing logic (20:00 ET)
            ep.airDateValue = DateUtils.parseEpisodeDate(airDate)
            season.episodes.append(ep)
            context.insert(ep)
        }
        
        try context.save()
        tvDetails.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE DROP")
    }

    @MainActor
    func testSeriesPremiereLogic() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "series_prem", title: "Series Premiere Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 102)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        context.insert(tvDetails)
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 8, showID: 102)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        context.insert(season)
        
        // Next ep is S1 E1, airing today (close to testNow)
        let airDate = "2026-04-29"
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "", airDate: airDate, showID: 102)
        ep1.season = season
        ep1.airDateValue = DateUtils.parseEpisodeDate(airDate)
        season.episodes.append(ep1)
        context.insert(ep1)
        
        try context.save()
        tvDetails.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "SERIES PREMIERE")
    }

    @MainActor
    func testSeasonPremiereLogic() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "season_prem", title: "Season Premiere Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 103)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        context.insert(tvDetails)
        
        let season2 = TVSeason(seasonNumber: 2, name: "Season 2", episodeCount: 10, showID: 103)
        season2.tvShowDetails = tvDetails
        tvDetails.seasons.append(season2)
        context.insert(season2)
        
        // Season 2 Ep 1 airing today
        let airDate = "2026-04-29"
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 2, name: "New Start", overview: "", airDate: airDate, showID: 103)
        ep1.season = season2
        ep1.airDateValue = DateUtils.parseEpisodeDate(airDate)
        season2.episodes.append(ep1)
        context.insert(ep1)
        
        try context.save()
        tvDetails.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "SEASON PREMIERE")
    }

    @MainActor
    func testPastPremiereDoesNotShowBadge() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
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
        
        // 10 days ago (relative to April 29)
        let airDate = "2026-04-19"
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "", airDate: airDate, showID: 104)
        ep1.season = season1
        ep1.airDateValue = DateUtils.parseDate(airDate)
        season1.episodes.append(ep1)
        
        item.releaseDate = DateUtils.parseDate(airDate)
        
        try context.save()
        tvDetails.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)
        
        XCTAssertNotEqual(item.storedSmartBadgeLabel, "SERIES PREMIERE")
        // It should be RECENT (within 14 days)
        XCTAssertEqual(item.storedSmartBadgeLabel, "RECENT")
    }

    @MainActor
    func testSoonBadgeLogic() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Movie releasing tomorrow (April 30)
        let movie = MediaItem(id: "soon_movie", title: "Soon Movie", overview: "", type: .movie)
        movie.releaseDate = DateUtils.parseDate("2026-04-30")
        context.insert(movie)
        
        try context.save()
        movie.syncCachedProperties(now: testNow)
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
        
        let airDate = "2026-04-30"
        let ep2 = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Ep 2", overview: "", airDate: airDate)
        ep2.season = season
        ep2.airDateValue = DateUtils.parseDate(airDate)
        season.episodes.append(ep2)
        
        try context.save()
        tvDetails.recalculateCachedProperties()
        show.syncCachedProperties(now: testNow)
        XCTAssertEqual(show.storedSmartBadgeLabel, "SOON")
    }

    @MainActor
    func testFinaleBadgeLogicFuture() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

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
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season2.episodes.append(ep)
            context.insert(ep)
        }
        
        // Finale airing in 11 days (May 10 relative to April 29)
        let airDate = "2026-05-10"
        let ep8 = TVEpisode(episodeNumber: 8, seasonNumber: 1, name: "Finale", overview: "", airDate: airDate)
        ep8.season = season2
        ep8.airDateValue = DateUtils.parseDate(airDate)
        season2.episodes.append(ep8)
        context.insert(ep8)
        
        try context.save()
        tvDetails2.recalculateCachedProperties()
        item2.syncCachedProperties(now: testNow)
        XCTAssertEqual(item2.storedSmartBadgeLabel, "FINALE")
    }
    
    @MainActor
    func testPeckingOrder() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Show that is both SOON (April 30) and SEASON PREMIERE
        let item = MediaItem(id: "multi_badge", title: "Multi Badge Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 106)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        let season = TVSeason(seasonNumber: 2, name: "Season 2", episodeCount: 10, showID: 106)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        let airDate = "2026-04-30"
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 2, name: "Ep 1", overview: "", airDate: airDate)
        ep1.season = season
        ep1.airDateValue = DateUtils.parseDate(airDate)
        season.episodes.append(ep1)
        context.insert(ep1)
        
        try context.save()
        tvDetails.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)
        
        // SEASON PREMIERE (LEVEL 1) > SOON (LEVEL 2)
        XCTAssertEqual(item.storedSmartBadgeLabel, "SEASON PREMIERE")
    }
}

extension DateFormatter {
    static let tmdb: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
