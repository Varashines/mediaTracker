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
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 3, showID: 105)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        // Released 10 days ago
        let airDate = "2026-04-15"
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep 1", overview: "", airDate: airDate, showID: 105)
        let ep2 = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Ep 2", overview: "", airDate: airDate, showID: 105)
        let ep3 = TVEpisode(episodeNumber: 3, seasonNumber: 1, name: "Ep 3", overview: "", airDate: airDate, showID: 105)
        
        [ep1, ep2, ep3].forEach { 
            $0.season = season
            season.episodes.append($0)
            context.insert($0)
        }
        
        item.syncCachedProperties()
        
        XCTAssertFalse(item.storedIsBingeDrop, "Should NOT be detected as Binge Drop (Too old)")
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE", "Should fall back to BINGE badge")
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
        
        // No episodes loaded yet, but nextEpisodeDate is in the past
        tvDetails.nextEpisodeDate = DateUtils.parseDate("2026-01-01")
        
        item.syncCachedProperties()
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE", "Watchlist multi-season show should be BINGE if available")
    }

    @MainActor
    func testBingeLogicForLikedShow() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 5. Setup a Liked show with < 80% progress (Available)
        let item = MediaItem(id: "liked_binge", title: "Liked Binge", overview: "Overview", type: .tvShow)
        item.state = .active
        item.tasteValue = "Like"
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 103)
        tvDetails.numberOfSeasons = 2
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 103)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        
        for i in 1...10 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2025-01-01", showID: 103)
            ep.isWatched = (i <= 5) // 50% progress
            ep.season = season
            season.episodes.append(ep)
        }
        
        item.syncCachedProperties()
        
        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE", "Liked show with 50% progress should be BINGE")
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
}
