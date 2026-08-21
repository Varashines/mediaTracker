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
    func testOnThisWeekFiltering() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let calendar = Calendar.current
        let today = Date()
        let todayMD = calendar.dateComponents([.month, .day], from: today)
        let currentYear = calendar.component(.year, from: today)

        // Item from previous year, same month+day as today — should match
        let matchItem = MediaItem(id: "1", title: "Last Year Today", overview: "", type: .movie)
        matchItem.releaseDate = calendar.date(from: DateComponents(year: currentYear - 1, month: todayMD.month!, day: todayMD.day!))!
        context.insert(matchItem)

        // Item from 2 years ago, same month+day — should match
        let matchItem2 = MediaItem(id: "2", title: "Two Years Ago", overview: "", type: .tvShow)
        matchItem2.releaseDate = calendar.date(from: DateComponents(year: currentYear - 2, month: todayMD.month!, day: todayMD.day!))!
        context.insert(matchItem2)

        // Item from current year, same month+day — should be excluded
        let currentYearItem = MediaItem(id: "3", title: "This Year", overview: "", type: .movie)
        currentYearItem.releaseDate = calendar.date(from: DateComponents(year: currentYear, month: todayMD.month!, day: todayMD.day!))!
        context.insert(currentYearItem)

        // Item from previous year, different month+day — should be excluded
        let noMatchItem = MediaItem(id: "4", title: "Wrong Day", overview: "", type: .movie)
        noMatchItem.releaseDate = calendar.date(from: DateComponents(year: currentYear - 1, month: 1, day: 15))!
        context.insert(noMatchItem)

        // Nil releaseDate — must be excluded
        let noDate = MediaItem(id: "5", title: "No Date", overview: "", type: .movie)
        context.insert(noDate)

        try context.save()

        let result = try await actor.filterAndSort(
            category: .onThisWeek,
            searchText: "",
            sortOrder: .newestRelease,
            network: nil,
            language: nil
        )

        let titles = result.displayed.map(\.title)
        XCTAssertTrue(titles.contains("Last Year Today"))
        XCTAssertTrue(titles.contains("Two Years Ago"))
        XCTAssertFalse(titles.contains("This Year"), "Current year should be excluded")
        XCTAssertFalse(titles.contains("Wrong Day"), "Different month+day should be excluded")
        XCTAssertFalse(titles.contains("No Date"))
        XCTAssertEqual(result.totalCount, 2)
    }

    @MainActor
    func testOnThisWeekMultipleDays() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let calendar = Calendar.current
        let today = Date()
        let currentYear = calendar.component(.year, from: today)
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        // Create items on each day of the week, from previous years
        for offset in 0..<7 {
            let dayDate = calendar.date(byAdding: .day, value: offset, to: startOfWeek)!
            let md = calendar.dateComponents([.month, .day], from: dayDate)
            let item = MediaItem(id: "\(offset + 10)", title: "Day \(offset)", overview: "", type: .movie)
            item.releaseDate = calendar.date(from: DateComponents(year: currentYear - 5, month: md.month!, day: md.day!))!
            context.insert(item)
        }

        try context.save()

        let result = try await actor.filterAndSort(
            category: .onThisWeek,
            searchText: "",
            sortOrder: .newestRelease,
            network: nil,
            language: nil
        )

        XCTAssertEqual(result.totalCount, 7, "Should include all 7 days of the week from previous years")
        let resultTitles = result.displayed.map(\.title)
        XCTAssertTrue(resultTitles.contains("Day 0"))
        XCTAssertTrue(resultTitles.contains("Day 6"))
    }

    @MainActor
    func testOnThisWeekBoundaryExcludesPrevWeek() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let calendar = Calendar.current
        let today = Date()
        let currentYear = calendar.component(.year, from: today)
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        // Day before this week starts (outside week range), previous year
        let beforeWeek = calendar.date(byAdding: .day, value: -1, to: startOfWeek)!
        let beforeMD = calendar.dateComponents([.month, .day], from: beforeWeek)
        let outsideItem = MediaItem(id: "30", title: "Before Week", overview: "", type: .movie)
        outsideItem.releaseDate = calendar.date(from: DateComponents(year: currentYear - 1, month: beforeMD.month!, day: beforeMD.day!))!
        context.insert(outsideItem)

        // First day of this week, previous year
        let firstDayMD = calendar.dateComponents([.month, .day], from: startOfWeek)
        let insideItem = MediaItem(id: "31", title: "First Day Week", overview: "", type: .movie)
        insideItem.releaseDate = calendar.date(from: DateComponents(year: currentYear - 1, month: firstDayMD.month!, day: firstDayMD.day!))!
        context.insert(insideItem)

        try context.save()

        let result = try await actor.filterAndSort(
            category: .onThisWeek,
            searchText: "",
            sortOrder: .newestRelease,
            network: nil,
            language: nil
        )

        let titles = result.displayed.map(\.title)
        XCTAssertFalse(titles.contains("Before Week"), "Day before week range should be excluded")
        XCTAssertTrue(titles.contains("First Day Week"), "First day of week range should be included")
    }

    @MainActor
    func testOnThisWeekExcludesCurrentYear() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let calendar = Calendar.current
        let today = Date()
        let currentYear = calendar.component(.year, from: today)
        let todayMD = calendar.dateComponents([.month, .day], from: today)

        // Current year, matching day — should be excluded
        let currentItem = MediaItem(id: "40", title: "Current Year Match", overview: "", type: .movie)
        currentItem.releaseDate = calendar.date(from: DateComponents(year: currentYear, month: todayMD.month!, day: todayMD.day!))!
        context.insert(currentItem)

        // Previous year, matching day — should be included
        let prevItem = MediaItem(id: "41", title: "Previous Year Match", overview: "", type: .movie)
        prevItem.releaseDate = calendar.date(from: DateComponents(year: currentYear - 3, month: todayMD.month!, day: todayMD.day!))!
        context.insert(prevItem)

        try context.save()

        let result = try await actor.filterAndSort(
            category: .onThisWeek,
            searchText: "",
            sortOrder: .newestRelease,
            network: nil,
            language: nil
        )

        let titles = result.displayed.map(\.title)
        XCTAssertFalse(titles.contains("Current Year Match"), "Same year should be excluded")
        XCTAssertTrue(titles.contains("Previous Year Match"), "Previous year should be included")
    }

    @MainActor
    func testSameWeekHelper() {
        let calendar = Calendar.current
        let today = Date()
        let currentYear = calendar.component(.year, from: today)
        let todayMD = calendar.dateComponents([.month, .day], from: today)
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        // Same date = same week (different year)
        let prevYearSameDay = calendar.date(from: DateComponents(year: currentYear - 1, month: todayMD.month!, day: todayMD.day!))!
        XCTAssertTrue(DateUtils.sameWeek(prevYearSameDay, today))

        // Day within this week's range, different year = same week
        let startMD = calendar.dateComponents([.month, .day], from: startOfWeek)
        let prevYearWeekStart = calendar.date(from: DateComponents(year: currentYear - 2, month: startMD.month!, day: startMD.day!))!
        XCTAssertTrue(DateUtils.sameWeek(prevYearWeekStart, today))

        // Same year = NOT same week (excluded)
        let thisYearDate = calendar.date(from: DateComponents(year: currentYear, month: todayMD.month!, day: todayMD.day!))!
        XCTAssertFalse(DateUtils.sameWeek(thisYearDate, today))

        // Day outside this week's range = NOT same week
        let outsideMD = calendar.date(byAdding: .day, value: -1, to: startOfWeek)!
        let outsideDateMD = calendar.dateComponents([.month, .day], from: outsideMD)
        let prevYearOutside = calendar.date(from: DateComponents(year: currentYear - 1, month: outsideDateMD.month!, day: outsideDateMD.day!))!
        XCTAssertFalse(DateUtils.sameWeek(prevYearOutside, today))
    }

    @MainActor
    func testWeekdayGroupingSortOrder() {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"

        let calendar = Calendar.current
        let today = Date()
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!

        let mondayStr = formatter.string(from: startOfWeek)
        let tuesdayStr = formatter.string(from: calendar.date(byAdding: .day, value: 1, to: startOfWeek)!)
        let thursdayStr = formatter.string(from: calendar.date(byAdding: .day, value: 3, to: startOfWeek)!)

        let keys = [thursdayStr, mondayStr, tuesdayStr]
        let sorted = keys.sorted { lhs, rhs in
            let lhsDate = formatter.date(from: lhs) ?? Date.distantPast
            let rhsDate = formatter.date(from: rhs) ?? Date.distantPast
            return calendar.compare(lhsDate, to: rhsDate, toGranularity: .day) == .orderedAscending
        }

        XCTAssertEqual(sorted[0], mondayStr, "Monday should sort first")
        XCTAssertEqual(sorted[1], tuesdayStr, "Tuesday should sort second")
        XCTAssertEqual(sorted[2], thursdayStr, "Thursday should sort last")
    }

    @MainActor
    func testDayOfWeekGrouping() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let todayMD = calendar.dateComponents([.month, .day], from: Date())
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!

        // Items on Monday, Tuesday, Thursday of the week in a previous year
        let mondayDate = startOfWeek
        let tuesdayDate = calendar.date(byAdding: .day, value: 1, to: startOfWeek)!
        let thursdayDate = calendar.date(byAdding: .day, value: 3, to: startOfWeek)!

        func makeItem(_ id: String, _ title: String, _ date: Date) -> MediaItem {
            let md = calendar.dateComponents([.month, .day], from: date)
            let item = MediaItem(id: id, title: title, overview: "", type: .movie)
            item.releaseDate = calendar.date(from: DateComponents(year: currentYear - 1, month: md.month!, day: md.day!))!
            return item
        }

        // Insert in shuffled order to verify chronological sorting
        context.insert(makeItem("3", "Thursday Item", thursdayDate))
        context.insert(makeItem("1", "Monday Item", mondayDate))
        context.insert(makeItem("2", "Tuesday Item", tuesdayDate))
        try context.save()

        let result = try await actor.filterAndSort(
            category: .all,
            searchText: "",
            sortOrder: .alphabetical,
            network: nil,
            language: nil,
            groupBy: .dayOfWeek
        )

        XCTAssertEqual(result.grouped.count, 3, "Should have 3 weekday groups")
        let mondayKey = DateUtils.weekdayDisplayString(for: mondayDate)
        let tuesdayKey = DateUtils.weekdayDisplayString(for: tuesdayDate)
        let thursdayKey = DateUtils.weekdayDisplayString(for: thursdayDate)

        XCTAssertEqual(result.grouped[0].0, mondayKey, "Monday should be first")
        XCTAssertEqual(result.grouped[1].0, tuesdayKey, "Tuesday should be second")
        XCTAssertEqual(result.grouped[2].0, thursdayKey, "Thursday should be last")
    }

    @MainActor
    func testHitScanCapFalseWhenLibraryUnderCap() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        for i in 0..<50 {
            let item = MediaItem(id: "under\(i)", title: "Show \(i)", overview: "", type: .tvShow)
            item.stateValue = "Active"
            context.insert(item)
            item.syncCachedProperties()
        }
        try context.save()

        // searchText forces Swift-level refinement (the capped scan path)
        let result = try await actor.filterAndSort(
            category: .all,
            searchText: "show",
            sortOrder: .alphabetical,
            network: nil,
            language: nil
        )
        XCTAssertFalse(result.hitScanCap, "Library under the candidate cap must not report hitScanCap")
        XCTAssertEqual(result.totalCount, 50)
    }

    @MainActor
    func testHitScanCapTrueWhenCandidateScanReachesCap() async throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let cap = LibraryScanLimits.refinementCandidateCap
        for i in 0..<(cap + 60) {
            let item = MediaItem(id: "over\(i)", title: "Show \(i)", overview: "", type: .tvShow)
            item.stateValue = "Active"
            context.insert(item)
            item.syncCachedProperties()
            if i % 250 == 0 { try context.save() }
        }
        try context.save()

        let result = try await actor.filterAndSort(
            category: .all,
            searchText: "show",
            sortOrder: .alphabetical,
            network: nil,
            language: nil
        )
        XCTAssertTrue(result.hitScanCap, "Candidate scan reaching the cap must report hitScanCap")
        XCTAssertEqual(result.totalCount, cap, "Refined total is derived from the capped scan")
    }
}
