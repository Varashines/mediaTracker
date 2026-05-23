import XCTest
import SwiftData
@testable import MediaTracker

final class BadgeEngineTests: XCTestCase {
    let nowString = "2026-04-29"
    var testNow: Date { DateUtils.parseDate(nowString)! }

    // MARK: - Level 0: Exclusions

    @MainActor
    func testDroppedShowReturnsNil() throws {
        let item = MediaItem(id: "1", title: "Dropped", overview: "", type: .tvShow)
        item.stateValue = "Dropped"
        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertNil(result)
    }

    @MainActor
    func testDroppedMovieReturnsNil() throws {
        let item = MediaItem(id: "2", title: "Dropped Movie", overview: "", type: .movie)
        item.stateValue = "Dropped"
        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertNil(result)
    }

    // MARK: - Level 1: Milestone Events - PREMIERE

    @MainActor
    func testPremiereForEpisode1WithinWindow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "p1", title: "Premiere Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 101)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 8)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "", airDate: "2026-04-29")
        ep1.season = season
        ep1.airDateValue = DateUtils.parseEpisodeDate("2026-04-29")
        season.episodes.append(ep1)
        context.insert(ep1)

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertEqual(item.storedSmartBadgeLabel, "PREMIERE")
    }

    @MainActor
    func testPremiereOutsidePastWindow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "p2", title: "Old Premiere", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 102)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 8)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        // 10 days ago - beyond the 3-day past limit
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "", airDate: "2026-04-19")
        ep1.season = season
        let oldDate = testNow.addingTimeInterval(-86400 * 10)
        ep1.airDateValue = oldDate
        season.episodes.append(ep1)
        context.insert(ep1)

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertNotEqual(item.storedSmartBadgeLabel, "PREMIERE")
    }

    @MainActor
    func testPremiereBeyondFutureWindow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "p3", title: "Far Premiere", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 103)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 8)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "")
        ep1.season = season
        let farDate = testNow.addingTimeInterval(86400 * 60)
        ep1.airDateValue = farDate
        season.episodes.append(ep1)
        context.insert(ep1)

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertNotEqual(item.storedSmartBadgeLabel, "PREMIERE")
    }

    // MARK: - Level 1: Milestone Events - FINALE

    @MainActor
    func testFinaleForLastEpisodeWithinWindow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "f1", title: "Finale Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 201)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        // Watch first 9 episodes
        for i in 1...9 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.season = season
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season.episodes.append(ep)
            context.insert(ep)
            ep.markWatched(true)
        }

        // Finale airing today
        let ep10 = TVEpisode(episodeNumber: 10, seasonNumber: 1, name: "Finale", overview: "", airDate: "2026-04-29")
        ep10.season = season
        ep10.airDateValue = DateUtils.parseEpisodeDate("2026-04-29")
        season.episodes.append(ep10)
        context.insert(ep10)

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertEqual(item.storedSmartBadgeLabel, "FINALE")
    }

    @MainActor
    func testFinaleOutsideWindow() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "f2", title: "Old Finale", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 202)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...9 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.season = season
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season.episodes.append(ep)
            context.insert(ep)
            ep.markWatched(true)
        }

        // Finale aired 30 days ago
        let ep10 = TVEpisode(episodeNumber: 10, seasonNumber: 1, name: "Finale", overview: "", airDate: "2026-03-30")
        ep10.season = season
        ep10.airDateValue = DateUtils.parseDate("2026-03-30")
        season.episodes.append(ep10)
        context.insert(ep10)

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertNotEqual(item.storedSmartBadgeLabel, "FINALE")
    }

    @MainActor
    func testFinaleWithNoAirDate() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "f3", title: "Undated Finale", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 203)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...9 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.season = season
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season.episodes.append(ep)
            context.insert(ep)
            ep.markWatched(true)
        }

        let ep10 = TVEpisode(episodeNumber: 10, seasonNumber: 1, name: "Finale", overview: "")
        ep10.season = season
        ep10.airDateValue = nil
        season.episodes.append(ep10)
        context.insert(ep10)

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertNil(item.storedSmartBadgeLabel)
    }

    // MARK: - Level 1: BINGE DROP

    @MainActor
    func testBingeDropMultipleEpisodesSameDay() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "bd1", title: "Binge Drop Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 301)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 5)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...5 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-04-29")
            ep.season = season
            ep.airDateValue = i == 1 ? testNow : DateUtils.parseEpisodeDate("2026-04-29")
            season.episodes.append(ep)
            context.insert(ep)
            if i == 1 { ep.markWatched(true) }
        }

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertEqual(item.storedSmartBadgeLabel, "BINGE DROP")
    }

    // MARK: - Level 2: NEW / SOON (Movie)

    @MainActor
    func testNewBadgeForMovieWithin14Days() throws {
        let item = MediaItem(id: "m1", title: "New Movie", overview: "", type: .movie)
        let tenDaysAgo = testNow.addingTimeInterval(-86400 * 10)
        item.releaseDate = tenDaysAgo
        item.cachedNextAiringDate = tenDaysAgo

        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertEqual(result?.label, .new)
    }

    @MainActor
    func testNewBadgeNotShownAfter14Days() throws {
        let item = MediaItem(id: "m2", title: "Old Movie", overview: "", type: .movie)
        let twentyDaysAgo = testNow.addingTimeInterval(-86400 * 20)
        item.releaseDate = twentyDaysAgo
        item.cachedNextAiringDate = twentyDaysAgo

        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertNil(result)
    }

    @MainActor
    func testSoonBadgeForTVShowWithin48Hours() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "s1", title: "Soon Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 301)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        // Episode 2 airing tomorrow - not a premiere, not a finale
        let tomorrow = testNow.addingTimeInterval(86400)
        let ep2 = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Ep 2", overview: "", airDate: "2026-04-30")
        ep2.season = season
        ep2.airDateValue = tomorrow
        season.episodes.append(ep2)
        context.insert(ep2)

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertEqual(item.storedSmartBadgeLabel, "SOON")
    }

    @MainActor
    func testSoonBadgeNotShownBeyond48Hours() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "s2", title: "Far Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 302)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let threeDays = testNow.addingTimeInterval(86400 * 3)
        let ep2 = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Ep 2", overview: "")
        ep2.season = season
        ep2.airDateValue = threeDays
        season.episodes.append(ep2)
        context.insert(ep2)

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertNotEqual(item.storedSmartBadgeLabel, "SOON")
    }

    @MainActor
    func testMoviePremiereWithinWindow() throws {
        let item = MediaItem(id: "m5", title: "Premiere Movie", overview: "", type: .movie)
        let oneDayAgo = testNow.addingTimeInterval(-86400)
        item.releaseDate = oneDayAgo
        item.cachedNextAiringDate = oneDayAgo

        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertEqual(result?.label, .premiere)
    }

    // MARK: - Level 3: Behavioral BINGE

    @MainActor
    func testBehavioralBingeWith3RecentWatched() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "bb1", title: "Binge Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 401)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        // 3 recently watched (within 48h)
        for i in 1...3 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.season = season
            ep.isWatched = true
            ep.lastWatchedDate = testNow.addingTimeInterval(-3600 * Double(i))
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season.episodes.append(ep)
            context.insert(ep)
        }
        // 1 unwatched
        let ep4 = TVEpisode(episodeNumber: 4, seasonNumber: 1, name: "Ep 4", overview: "", airDate: "2026-01-01")
        ep4.season = season
        ep4.airDateValue = DateUtils.parseDate("2026-01-01")
        ep4.isWatched = false
        season.episodes.append(ep4)
        context.insert(ep4)

        try context.save()
        _ = tv.calculateProgress(now: testNow)
        // Ensure remaining > 0
        tv.remainingEpisodesCount = 1

        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertEqual(result?.label, .binge)
        XCTAssertTrue(result!.isSparkle)
    }

    @MainActor
    func testNoBingeWhenCompleted() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "bb2", title: "Completed Binge", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 402)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 3)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...3 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.season = season
            ep.isWatched = true
            ep.lastWatchedDate = testNow.addingTimeInterval(-3600 * Double(i))
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season.episodes.append(ep)
            context.insert(ep)
        }

        try context.save()
        _ = tv.calculateProgress(now: testNow)
        tv.remainingEpisodesCount = 0

        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertNotEqual(result?.label, .binge)
    }

    // MARK: - Level 3: BEHIND

    @MainActor
    func testBehindBadgeForLikedShowWithNextAiringSoon() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "bh1", title: "Behind Show", overview: "", type: .tvShow)
        item.taste = .like
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 501)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let pastDate = testNow.addingTimeInterval(-86400 * 7) // 7 days before testNow
        for i in 1...5 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.season = season
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season.episodes.append(ep)
            context.insert(ep)
            ep.isWatched = i <= 3
            ep.lastWatchedDate = pastDate
        }

        tv.remainingEpisodesCount = 2
        tv.totalEpisodesCount = 10
        tv.watchedEpisodesCount = 3
        item.cachedNextAiringDate = testNow.addingTimeInterval(86400 * 3) // 3 days away

        try context.save()

        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertEqual(result?.label, .behind)
        XCTAssertFalse(result!.isSparkle)
    }

    // MARK: - Level 3: BACKLOG BINGE

    @MainActor
    func testBacklogBingeAt20PercentProgress() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "bl1", title: "Backlog Show", overview: "", type: .tvShow)
        item.taste = .like
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 601)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...10 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.season = season
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season.episodes.append(ep)
            context.insert(ep)
            ep.markWatched(i <= 2) // 2/10 = 20%
        }

        try context.save()
        tv.totalEpisodesCount = 10
        tv.watchedEpisodesCount = 2
        tv.remainingEpisodesCount = 8

        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertEqual(result?.label, .binge)
        XCTAssertFalse(result!.isSparkle)
    }

    @MainActor
    func testNoBacklogBingeBelow20Percent() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "bl2", title: "No Backlog Show", overview: "", type: .tvShow)
        item.taste = .like
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 602)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        for i in 1...10 {
            let ep = TVEpisode(episodeNumber: i, seasonNumber: 1, name: "Ep \(i)", overview: "", airDate: "2026-01-01")
            ep.season = season
            ep.airDateValue = DateUtils.parseDate("2026-01-01")
            season.episodes.append(ep)
            context.insert(ep)
            ep.markWatched(i <= 1) // 1/10 = 10%
        }

        try context.save()
        tv.totalEpisodesCount = 10
        tv.watchedEpisodesCount = 1

        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertNil(result)
    }

    // MARK: - Pecking Order

    @MainActor
    func testPremiereOverridesSoon() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "po1", title: "Pecking Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 701)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 2, name: "S2", episodeCount: 10)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        // Season premiere tomorrow (both PREMIERE and SOON eligible)
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 2, name: "S2 Premiere", overview: "", airDate: "2026-04-30")
        ep1.season = season
        ep1.airDateValue = DateUtils.parseDate("2026-04-30")
        season.episodes.append(ep1)
        context.insert(ep1)

        try context.save()
        tv.recalculateCachedProperties()
        item.syncCachedProperties(now: testNow)

        XCTAssertEqual(item.storedSmartBadgeLabel, "PREMIERE")
    }

    // MARK: - State Exclusion: Dropped

    @MainActor
    func testAllBadgeLevelsSkippedWhenDropped() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "dr1", title: "Dropped Show", overview: "", type: .tvShow)
        item.stateValue = "Dropped"
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 801)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 8)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Pilot", overview: "", airDate: "2026-04-29")
        ep1.season = season
        ep1.airDateValue = DateUtils.parseEpisodeDate("2026-04-29")
        season.episodes.append(ep1)
        context.insert(ep1)

        try context.save()
        let result = BadgeEngine.calculateBadge(for: item, now: testNow)
        XCTAssertNil(result)
    }
}
