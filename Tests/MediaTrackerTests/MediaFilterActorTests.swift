import XCTest
import SwiftData
@testable import MediaTracker

final class MediaFilterActorTests: XCTestCase {
    @MainActor
    func testHomeContinueWatchingSorting() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let actor = MediaFilterActor(modelContainer: container)
        
        // Create 3 items
        // 1. Active, NEW, older interaction
        let item1 = MediaItem(id: "1", title: "Streaming Old", overview: "", type: .tvShow)
        item1.stateValue = "Active"
        item1.lastInteractionDate = Date().addingTimeInterval(-2000)
        item1.releaseDate = Date().addingTimeInterval(-100000) // Within 48h (NEW)
        context.insert(item1)
        
        // 2. Active, NOT NEW, newer interaction
        let item2 = MediaItem(id: "2", title: "Active New", overview: "", type: .tvShow)
        item2.stateValue = "Active"
        item2.lastInteractionDate = Date()
        item2.releaseDate = Date().addingTimeInterval(-20 * 86400) // Outside 14-day window
        context.insert(item2)
        
        // 3. Active, NEW, newest interaction
        let item3 = MediaItem(id: "3", title: "Streaming New", overview: "", type: .tvShow)
        item3.stateValue = "Active"
        item3.lastInteractionDate = Date().addingTimeInterval(2000)
        item3.releaseDate = Date().addingTimeInterval(-50000) // Within 48h (NEW)
        context.insert(item3)
        
        // Manual sync to ensure badges are set correctly by BadgeEngine
        item1.syncCachedProperties()
        item2.syncCachedProperties()
        item3.syncCachedProperties()
        
        try context.save()
        
        let result = try await actor.filterAndSort(
            category: .home,
            searchText: "",
            sortOrder: .alphabetical,
            network: nil,
            language: nil,
            genre: nil,
            year: nil,
            state: nil,
            badge: nil
        )
        
        let continueWatching = result.homeContinueWatching
        
        XCTAssertEqual(continueWatching.count, 3)
        
        // Expected order:
        // 1. Item 3 (NEW badge, newest interaction)
        // 2. Item 1 (NEW badge, older interaction)
        // 3. Item 2 (No NEW badge, newest interaction)
        
        XCTAssertEqual(continueWatching[0].title, "Streaming New")
        XCTAssertEqual(continueWatching[1].title, "Streaming Old")
        XCTAssertEqual(continueWatching[2].title, "Active New")
    }

    @MainActor
    func testFetchCalendarDataLazyLoading() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        let actor = CalendarFilterActor(modelContainer: container)
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let components = calendar.dateComponents([.year, .month], from: today)
        let firstOfMonth = calendar.date(from: components)!
        
        // Item in current month
        let item1 = MediaItem(id: "1", title: "Current Month", overview: "", type: .movie)
        item1.cachedNextAiringDate = firstOfMonth.addingTimeInterval(86400) // 2nd of month
        context.insert(item1)
        
        // Item in next month
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth)!
        let item2 = MediaItem(id: "2", title: "Next Month", overview: "", type: .movie)
        item2.cachedNextAiringDate = nextMonth.addingTimeInterval(86400)
        context.insert(item2)
        
        try context.save()
        
        // Fetch current month
        let result = try await actor.fetchCalendarData(for: firstOfMonth)
        
        // Check current month results
        XCTAssertTrue(result.days.values.flatMap { $0.items }.contains { $0.metadata.title == "Current Month" })
        XCTAssertFalse(result.days.values.flatMap { $0.items }.contains { $0.metadata.title == "Next Month" })
        
        // Fetch next month
        let resultNext = try await actor.fetchCalendarData(for: nextMonth)
        XCTAssertTrue(resultNext.days.values.flatMap { $0.items }.contains { $0.metadata.title == "Next Month" })
        XCTAssertFalse(resultNext.days.values.flatMap { $0.items }.contains { $0.metadata.title == "Current Month" })
    }

    @MainActor
    func testEpisodeGrouping() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = CalendarFilterActor(modelContainer: container)
        
        let calendar = Calendar.current
        let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        let airDate = calendar.date(byAdding: .day, value: 5, to: firstOfMonth)!
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let airDateString = formatter.string(from: airDate)

        let show = MediaItem(id: "100", title: "Binge Show", overview: "", type: .tvShow)
        context.insert(show)
        let tvDetails = TVShowDetails(tmdbID: 100)
        tvDetails.item = show
        context.insert(tvDetails)
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 100)
        season.tvShowDetails = tvDetails
        context.insert(season)
        
        let ep1 = TVEpisode(episodeNumber: 1, seasonNumber: 1, name: "Ep 1", overview: "", airDate: airDateString)
        ep1.season = season
        ep1.airDateValue = airDate
        context.insert(ep1)
        let ep2 = TVEpisode(episodeNumber: 2, seasonNumber: 1, name: "Ep 2", overview: "", airDate: airDateString)
        ep2.season = season
        ep2.airDateValue = airDate
        context.insert(ep2)
        
        try context.save()
        
        let result = try await actor.fetchCalendarData(for: firstOfMonth)
        
        // Should have 1 entry for the show on that day
        let day = calendar.startOfDay(for: airDate)
        let dayItems = result.days[day]?.items ?? []
        
        XCTAssertEqual(dayItems.count, 1)
        XCTAssertEqual(dayItems.first?.releaseContext, "S1 E1, E2")
    }

    @MainActor
    func testFetchMetadataIfMatchesReturnsItem() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let meta = try await actor.fetchMetadataIfMatches(for: item.persistentModelID, category: .all, searchText: "")

        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.title, "Test")
    }

    @MainActor
    func testFetchMetadataIfMatchesReturnsNilForNoMatch() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        // Search for something that doesn't match
        let meta = try await actor.fetchMetadataIfMatches(for: item.persistentModelID, category: .all, searchText: "nonexistent")

        XCTAssertNil(meta)
    }

    @MainActor
    func testToMetadataProducesCorrectMapping() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Test Movie", overview: "An overview", type: .movie)
        item.stateValue = "Completed"
        item.storedProgress = 1.0
        item.storedSmartBadgeLabel = "NEW"
        item.storedSmartBadgeIsSparkle = true
        item.cachedGenres = ["Action"]
        context.insert(item)
        try context.save()

        let meta = MediaThumbnailMetadata(item: item)

        XCTAssertEqual(meta.title, "Test Movie")
        XCTAssertEqual(meta.state, .completed)
        XCTAssertEqual(meta.progress, 1.0)
        XCTAssertEqual(meta.smartBadgeLabel, "NEW")
        XCTAssertEqual(meta.genres, ["Action"])
    }

    @MainActor
    func testOnThisDayFiltering() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let calendar = Calendar.current
        let today = Date()
        let recentYear = calendar.date(byAdding: .year, value: -1, to: today)! // same month/day, previous year
        let classicYear = calendar.date(byAdding: .year, value: -25, to: today)! // same month/day, 25 years ago
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        // Same month/day, recent year
        let recent = MediaItem(id: "1", title: "Recent Premier", overview: "", type: .movie)
        recent.releaseDate = recentYear
        context.insert(recent)

        // Same month/day, older year
        let classic = MediaItem(id: "2", title: "Classic Premier", overview: "", type: .tvShow)
        classic.releaseDate = classicYear
        context.insert(classic)

        // Different month/day — must be excluded
        let wrongDay = MediaItem(id: "3", title: "Other Day", overview: "", type: .movie)
        wrongDay.releaseDate = tomorrow
        context.insert(wrongDay)

        // Nil releaseDate — must be excluded
        let noDate = MediaItem(id: "4", title: "No Date", overview: "", type: .movie)
        context.insert(noDate)

        try context.save()

        let result = try await actor.filterAndSort(
            category: .onThisDay,
            searchText: "",
            sortOrder: .newestRelease,
            network: nil,
            language: nil
        )

        let titles = result.displayed.map(\.title)
        XCTAssertEqual(titles, ["Recent Premier", "Classic Premier"])
        XCTAssertEqual(result.totalCount, 2)
    }
}
