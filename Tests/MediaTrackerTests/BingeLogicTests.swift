import XCTest
import SwiftData
@testable import MediaTracker

final class BingeLogicTests: XCTestCase {
    // Current date in session is Saturday, 25 April 2026
    let nowString = "2026-04-25"

    @MainActor
    func testBingeDropLogic() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 1. Setup a show with multiple episodes on the same day (Recent Binge Drop)
        let item = MediaItem(id: "binge_drop_show", title: "Binge Drop Show", overview: "Overview", type: .tvShow)
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 101)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 3, showID: 101)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // Released 2 days ago
        let airDate = "2026-04-23"
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep 1", overview: "", airDate: airDate, showID: 101)
        let ep2 = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Ep 2", overview: "", airDate: airDate, showID: 101)
        let ep3 = TVEpisode(episodeNumber: 3, seasonNumber: 1, name: "Ep 3", overview: "", airDate: airDate, showID: 101)
        
        [ep1, ep2, ep3].forEach { 
            $0.season = season
            season.episodes.append($0)
            context.insert($0)
        }
        
        item.syncCachedProperties()
        
        XCTAssertTrue(item.storedIsBingeDrop, "Should be detected as Binge Drop (Recent)")
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE DROP")
    }

    @MainActor
    func testOldBingeDropFallsBackToBinge() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 2. Setup a show with multiple episodes on the same day but > 5 days ago
        let item = MediaItem(id: "old_binge_drop", title: "Old Binge Drop", overview: "Overview", type: .tvShow)
        item.tasteValue = "Like"
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 105)
        tvDetails.numberOfSeasons = 2
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 105)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // Released 10 days ago, with 40% progress
        let airDate = "2026-04-15"
        for i in 1...10 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: airDate, showID: 105)
            ep.isWatched = (i <= 4)
            ep.season = season
            season.episodes.append(ep)
            context.insert(ep)
        }
        
        item.syncCachedProperties()
        
        XCTAssertFalse(item.storedIsBingeDrop, "Should NOT be detected as Binge Drop (Too old)")
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE", "Should fall back to BINGE badge with 40% progress")
    }

    @MainActor
    func testFutureEpisodePreventsBingeBadge() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 3. Show in Watchlist but next episode is in future
        let item = MediaItem(id: "future_binge", title: "Future Binge", overview: "Overview", type: .tvShow)
        item.state = .wishlist
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 106)
        tvDetails.numberOfSeasons = 2
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 3, showID: 106)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // Released in the future
        let airDate = "2026-05-01"
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep 1", overview: "", airDate: airDate, showID: 106)
        
        ep1.season = season
        season.episodes.append(ep1)
        context.insert(ep1)
        
        item.syncCachedProperties()
        
        XCTAssertNil(item.storedSmartBadgeLabel, "Should NOT have BINGE badge if next episode is in the future")
    }

    @MainActor
    func testBingeLogicForWatchlist() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 4. Setup a multi-season show in Watchlist (Available)
        let item = MediaItem(id: "watchlist_binge", title: "Watchlist Binge", overview: "Overview", type: .tvShow)
        item.state = .wishlist
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 102)
        tvDetails.numberOfSeasons = 3
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        // No episodes loaded yet = 0 progress
        tvDetails.nextEpisodeDate = DateUtils.parseDate("2026-01-01")
        
        item.syncCachedProperties()
        
        XCTAssertNil(item.storedSmartBadgeLabel, "Watchlist show with 0 progress should NOT be BINGE")
        
        // Now give it 35% progress
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 102)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        for i in 1...10 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01", showID: 102)
            ep.isWatched = (i <= 3)
            ep.season = season
            season.episodes.append(ep)
        }
        
        item.syncCachedProperties()
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE", "Watchlist show with 30% progress should be BINGE")
    }

    @MainActor
    func testBingeLogicForLikedShow() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 5. Setup a Liked show with 20% progress (Below 30% threshold)
        let item = MediaItem(id: "liked_binge", title: "Liked Binge", overview: "Overview", type: .tvShow)
        item.state = .active
        item.tasteValue = "Like"
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 103)
        tvDetails.numberOfSeasons = 2
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 20, showID: 103)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        for i in 1...20 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2025-01-01", showID: 103)
            ep.isWatched = (i <= 4) // 20% progress
            ep.season = season
            season.episodes.append(ep)
        }
        
        item.syncCachedProperties()
        XCTAssertNil(item.storedSmartBadgeLabel, "Liked show with < 30% progress should NOT be BINGE")
        
        // Give it 90% progress (No max threshold)
        for i in 5...18 {
            season.episodes[i-1].isWatched = true
        }
        
        item.syncCachedProperties()
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE", "Liked show with 90% progress should be BINGE")
    }
    
    @MainActor
    func testPriorityBingeDropOverFinale() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 6. Recent Binge Drop with 3 episodes. 
        let item = MediaItem(id: "priority_show", title: "Priority Show", overview: "Overview", type: .tvShow)
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 104)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 3, showID: 104)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        let airDate = "2026-04-24" // Yesterday
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep 1", overview: "", airDate: airDate, showID: 104)
        let ep2 = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Ep 2", overview: "", airDate: airDate, showID: 104)
        let ep3 = TVEpisode(episodeNumber: 3, seasonNumber: 1, name: "Ep 3", overview: "", airDate: airDate, showID: 104)
        
        [ep1, ep2, ep3].forEach { 
            $0.season = season
            season.episodes.append($0)
            context.insert($0)
        }
        
        // Scenario A: On Ep 1 (3 left) -> BINGE DROP
        item.syncCachedProperties()
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE DROP")
        
        // Scenario B: On Ep 2 (2 left) -> BINGE DROP
        ep1.isWatched = true
        item.syncCachedProperties()
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE DROP")
        
        // Scenario C: On Ep 3 (1 left) -> FINALE
        ep2.isWatched = true
        item.syncCachedProperties()
        XCTAssertEqual(item.storedSmartBadgeLabel, "FINALE")
    }

    @MainActor
    func testSeasonZeroIgnored() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 7. Show with ONLY Season 0 episodes
        let item = MediaItem(id: "season_zero_show", title: "Season Zero Show", overview: "Overview", type: .tvShow)
        item.tasteValue = "Love"
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 107)
        tvDetails.numberOfSeasons = 1
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season0 = TVSeason(seasonNumber: 0, name: "Specials", episodeCount: 5, showID: 107)
        season0.tvShowDetails = tvDetails
        tvDetails.seasons.append(season0)
        
        for i in 1...5 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 0, name: "Special \(i)", overview: "", airDate: "2020-01-01", showID: 107)
            ep.season = season0
            season0.episodes.append(ep)
        }
        
        item.syncCachedProperties()
        
        XCTAssertNil(item.storedSmartBadgeLabel, "Should NOT have any smart badges if only Season 0 exists")
        XCTAssertNil(item.storedWatchProgressLabel, "Progress label should be nil for Season 0 only shows")
        XCTAssertEqual(item.storedProgress, 0, "Progress should be 0 for Season 0 shows")
    }

    @MainActor
    func testMissingAirDatePreventsBadges() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 8. Show with missing air date on next episode
        let item = MediaItem(id: "missing_date_show", title: "Missing Date Show", overview: "Overview", type: .tvShow)
        item.state = .wishlist
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 108)
        tvDetails.numberOfSeasons = 2
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 1, showID: 108)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep 1", overview: "", airDate: nil, showID: 108)
        ep1.season = season
        season.episodes.append(ep1)
        context.insert(ep1)
        
        item.syncCachedProperties()
        
        XCTAssertNil(item.storedSmartBadgeLabel, "Should NOT have BINGE or FINALE badge if air date is missing")
    }

    @MainActor
    func testStreamingPriorityOverBinge() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 9. Show with 70% progress, Loved, Ep 8 aired TODAY, Ep 9-10 in FUTURE.
        // Today is April 27, 2026
        let item = MediaItem(id: "streaming_priority", title: "Streaming Priority Show", overview: "Overview", type: .tvShow)
        item.tasteValue = "Love"
        item.state = .active
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 109)
        tvDetails.numberOfSeasons = 1
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 109)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // 1-7 Watched (Long ago)
        for i in 1...7 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01", showID: 109)
            ep.isWatched = true
            ep.season = season
            season.episodes.append(ep)
        }
        
        // 8 Aired TODAY (April 27, 2026)
        let ep8 = TVEpisode(episodeNumber: 8, seasonNumber: 1, name: "Ep 8", overview: "", airDate: "2026-04-27", showID: 109)
        ep8.isWatched = false
        ep8.season = season
        season.episodes.append(ep8)
        
        // 9-10 Future
        let ep9 = TVEpisode(episodeNumber: 9, seasonNumber: 1, name: "Ep 9", overview: "", airDate: "2026-05-04", showID: 109)
        let ep10 = TVEpisode(episodeNumber: 10, seasonNumber: 1, name: "Ep 10", overview: "", airDate: "2026-05-11", showID: 109)
        [ep9, ep10].forEach {
            $0.isWatched = false
            $0.season = season
            season.episodes.append($0)
        }
        
        item.syncCachedProperties()
        
        // Should be STREAMING because Ep 8 just aired
        XCTAssertEqual(item.storedSmartBadgeLabel, "STREAMING", "Should be STREAMING because Ep 8 just aired")
        
        // Remaining count should be 1 (Only Ep 8)
        XCTAssertEqual(item.remainingEpisodesCount, 1, "Remaining count should only include aired episodes")
        
        // Now test BINGE fallback with multiple episodes aired more than 2 days ago
        ep8.airDate = "2026-04-20" // 7 days ago
        // Add another aired episode to trigger BINGE (> 1 remaining)
        ep9.airDate = "2026-04-21" // 6 days ago
        
        item.syncCachedProperties()
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE", "Should fall back to BINGE after streaming window passes and multiple episodes are available")
        XCTAssertEqual(item.remainingEpisodesCount, 2, "Remaining count should be 2")
    }
}
