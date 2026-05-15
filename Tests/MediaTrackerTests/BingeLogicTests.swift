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
            if i == 1 { ep.markWatched(true) } // Mark first watched to avoid Premiere priority
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
    func testPremiereLogic() async throws {
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
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "PREMIERE")
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
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "PREMIERE")
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
        
        // 10 days ago is too old for PREMIERE (now 3 days)
        XCTAssertNotEqual(item.storedSmartBadgeLabel, "PREMIERE")
        // But it's within 14 days, so it gets NEW
        XCTAssertEqual(item.storedSmartBadgeLabel, "NEW")
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
        XCTAssertEqual(movie.storedSmartBadgeLabel, "PREMIERE")
        
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
    func testFinaleBadgeLogicRecent() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item2 = MediaItem(id: "recent_finale_8", title: "Recent Finale 8", overview: "", type: .tvShow)
        context.insert(item2)
        let tvDetails2 = TVShowDetails(tmdbID: 106)
        tvDetails2.item = item2
        item2.tvShowDetails = tvDetails2
        let season2 = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 8, showID: 106)
        season2.tvShowDetails = tvDetails2
        tvDetails2.seasons.append(season2)
        
        for i in 1...7 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.markWatched(true)
            ep.season = season2
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season2.episodes.append(ep)
            context.insert(ep)
        }
        
        // Finale airing in 3 days (May 2 relative to April 29)
        let airDate = "2026-05-02"
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
    func testOldFinaleDoesNotShowBadge() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "old_finale", title: "Old Finale Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 107)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 107)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // Finale aired 30 days ago
        let airDate = "2026-03-30"
        let ep10 = TVEpisode(episodeNumber: 10, seasonNumber: 1, name: "The End", overview: "", airDate: airDate)
        ep10.season = season
        ep10.airDateValue = DateUtils.parseDate(airDate)
        season.episodes.append(ep10)
        
        try context.save()
        tvDetails.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)
        
        XCTAssertNotEqual(item.storedSmartBadgeLabel, "FINALE")
    }
    
    @MainActor
    func testUndatedFinaleDoesNotShowBadge() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "undated_finale", title: "Undated Finale Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 108)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 108)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // Finale with NO air date
        let ep10 = TVEpisode(episodeNumber: 10, seasonNumber: 1, name: "The End", overview: "", airDate: nil)
        ep10.season = season
        ep10.airDateValue = nil
        season.episodes.append(ep10)
        
        try context.save()
        tvDetails.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)
        
        XCTAssertNil(item.storedSmartBadgeLabel)
    }

    @MainActor
    func testPeckingOrder() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Show that is both SOON (April 30) and PREMIERE
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
        
        // PREMIERE (LEVEL 1) > SOON (LEVEL 2)
        XCTAssertEqual(item.storedSmartBadgeLabel, "PREMIERE")
    }

    @MainActor
    func testBehavioralBingeLogic() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "behavioral_binge", title: "Binge Show", overview: "", type: .tvShow)
        context.insert(item)
        let tvDetails = TVShowDetails(tmdbID: 107)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        context.insert(tvDetails)
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 107)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        context.insert(season)
        
        // Use a fixed testNow for consistency
        let fixedNow = DateUtils.parseDate("2026-04-29")!
        
        // Mark 3 episodes as watched recently (relative to fixedNow)
        for i in 1...3 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.season = season
            ep.isWatched = true
            ep.lastWatchedDate = fixedNow.addingTimeInterval(-3600 * Double(i)) // Within last few hours
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season.episodes.append(ep)
            context.insert(ep)
        }
        
        // Add one unwatched episode that aired in the past to avoid "Completed" state
        let ep4 = TVEpisode(episodeNumber: 4, seasonNumber: 1, name: "Ep 4", overview: "", airDate: "2026-01-01")
        ep4.season = season
        ep4.airDateValue = DateUtils.parseDate("2026-01-01")
        ep4.isWatched = false
        season.episodes.append(ep4)
        context.insert(ep4)
        
        try context.save()
        
        // Ensure denormalized counts are set for the mock time
        _ = tvDetails.calculateProgress(now: fixedNow)
        
        // Manually trigger the sync with the fixed time
        item.syncCachedProperties(now: fixedNow)
        
        // Should show BINGE because 3 episodes were watched recently and there are remaining episodes
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE")
        
        // Now mark ep4 as watched and sync again
        ep4.markWatched(true)
        ep4.lastWatchedDate = fixedNow
        try context.save()
        item.syncCachedProperties(now: fixedNow)
        
        // Should NOT show BINGE because it's now a completed series (remainingCount == 0)
        XCTAssertNotEqual(item.storedSmartBadgeLabel, "BINGE")
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
