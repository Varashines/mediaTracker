import XCTest
import SwiftData
@testable import MediaTracker

final class FilterAndSortTests: XCTestCase {
    @MainActor
    func makeContainer() -> ModelContainer {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    func testFilterByCategoryAll() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let movie = MediaItem(id: "m1", title: "Movie Alpha", overview: "", type: .movie)
        context.insert(movie)
        let show = MediaItem(id: "t1", title: "Show Beta", overview: "", type: .tvShow)
        context.insert(show)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: nil, language: nil)

        XCTAssertEqual(result.totalCount, 2)
        XCTAssertEqual(result.displayed.count, 2)
        XCTAssertEqual(result.displayed[0].title, "Movie Alpha")
        XCTAssertEqual(result.displayed[1].title, "Show Beta")
    }

    @MainActor
    func testFilterByMovieCategory() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let movie = MediaItem(id: "m1", title: "Movie", overview: "", type: .movie)
        context.insert(movie)
        let show = MediaItem(id: "t1", title: "Show", overview: "", type: .tvShow)
        context.insert(show)
        try context.save()

        let result = try await actor.filterAndSort(category: .movie, searchText: "", sortOrder: .alphabetical, network: nil, language: nil)

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.displayed[0].title, "Movie")
    }

    @MainActor
    func testFilterByTVShowCategory() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let movie = MediaItem(id: "m1", title: "Movie", overview: "", type: .movie)
        context.insert(movie)
        let show = MediaItem(id: "t1", title: "Show", overview: "", type: .tvShow)
        context.insert(show)
        try context.save()

        let result = try await actor.filterAndSort(category: .tvShow, searchText: "", sortOrder: .alphabetical, network: nil, language: nil)

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.displayed[0].title, "Show")
    }

    @MainActor
    func testSearchTextFiltersResults() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let matching = MediaItem(id: "1", title: "Dark Knight", overview: "", type: .movie)
        matching.searchableText = "dark knight"
        context.insert(matching)
        let notMatching = MediaItem(id: "2", title: "Inception", overview: "", type: .movie)
        notMatching.searchableText = "inception"
        context.insert(notMatching)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "dark", sortOrder: .alphabetical, network: nil, language: nil)

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.displayed[0].title, "Dark Knight")
    }

    @MainActor
    func testFilterByCompletedState() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let completed = MediaItem(id: "1", title: "Done", overview: "", type: .movie)
        completed.stateValue = "Completed"
        context.insert(completed)
        let active = MediaItem(id: "2", title: "In Progress", overview: "", type: .movie)
        active.stateValue = "Active"
        context.insert(active)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: nil, language: nil, state: .completed)

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.displayed[0].title, "Done")
    }

    @MainActor
    func testFilterByBadge() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let withBadge = MediaItem(id: "1", title: "New Release", overview: "", type: .movie)
        withBadge.storedSmartBadgeLabel = "NEW"
        withBadge.searchableText = "new release"
        context.insert(withBadge)
        let withoutBadge = MediaItem(id: "2", title: "Old Movie", overview: "", type: .movie)
        withoutBadge.searchableText = "old movie"
        context.insert(withoutBadge)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: nil, language: nil, badge: "NEW")

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.displayed[0].title, "New Release")
    }

    @MainActor
    func testFilterByLanguage() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let english = MediaItem(id: "1", title: "English Film", overview: "", type: .movie)
        english.cachedLanguage = "en"
        english.searchableText = "english film"
        context.insert(english)
        let french = MediaItem(id: "2", title: "Film Français", overview: "", type: .movie)
        french.cachedLanguage = "fr"
        french.searchableText = "film francais"
        context.insert(french)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: nil, language: "en")

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.displayed[0].title, "English Film")
    }

    @MainActor
    func testSortByNewestRelease() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let older = MediaItem(id: "1", title: "Old", overview: "", type: .movie)
        older.releaseDate = Date(timeIntervalSince1970: 0)
        context.insert(older)
        let newer = MediaItem(id: "2", title: "New", overview: "", type: .movie)
        newer.releaseDate = Date(timeIntervalSince1970: 1000000)
        context.insert(newer)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .newestRelease, network: nil, language: nil)

        XCTAssertEqual(result.totalCount, 2)
        XCTAssertEqual(result.displayed[0].title, "New")
        XCTAssertEqual(result.displayed[1].title, "Old")
    }

    @MainActor
    func testGroupByGenre() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let action = MediaItem(id: "1", title: "Action Film", overview: "", type: .movie)
        action.cachedGenres = ["Action"]
        context.insert(action)
        let drama = MediaItem(id: "2", title: "Drama Film", overview: "", type: .movie)
        drama.cachedGenres = ["Drama"]
        context.insert(drama)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: nil, language: nil, groupBy: .genre)

        let genreNames = result.grouped.map { $0.0 }.sorted()
        XCTAssertTrue(genreNames.contains("Action"))
        XCTAssertTrue(genreNames.contains("Drama"))
    }

    @MainActor
    func testPaginationWithLimit() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        for i in 1...5 {
            let item = MediaItem(id: "\(i)", title: "Item \(i)", overview: "", type: .movie)
            context.insert(item)
        }
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: nil, language: nil, limit: 2, offset: 0)

        XCTAssertEqual(result.displayed.count, 2)
        XCTAssertEqual(result.totalCount, 5)
    }

    @MainActor
    func testAllLibraryTMDBIDs() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        for i in 1...3 {
            let item = MediaItem(id: "id_\(i)", title: "Item \(i)", overview: "", type: .movie)
            context.insert(item)
        }
        try context.save()

        let ids = try await actor.allLibraryTMDBIDs()
        XCTAssertEqual(ids, ["id_1", "id_2", "id_3"])
    }

    @MainActor
    func testFilterWithNetwork() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let netflix = MediaItem(id: "1", title: "Netflix Show", overview: "", type: .tvShow)
        netflix.cachedNetwork = "Netflix"
        netflix.searchableText = "netflix show"
        context.insert(netflix)
        let amazon = MediaItem(id: "2", title: "Amazon Show", overview: "", type: .tvShow)
        amazon.cachedNetwork = "Amazon Prime"
        amazon.searchableText = "amazon show"
        context.insert(amazon)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: ["Netflix"], language: nil)

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.displayed[0].title, "Netflix Show")
    }

    @MainActor
    func testFilterWithGenre() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let action = MediaItem(id: "1", title: "Action Movie", overview: "", type: .movie)
        action.cachedGenres = ["Action"]
        action.searchableText = "action movie"
        context.insert(action)
        let drama = MediaItem(id: "2", title: "Drama Movie", overview: "", type: .movie)
        drama.cachedGenres = ["Drama"]
        drama.searchableText = "drama movie"
        context.insert(drama)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: nil, language: nil, genre: "Action")

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.displayed[0].title, "Action Movie")
    }

    @MainActor
    func testFilterWithYear() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let old = MediaItem(id: "1", title: "Old Movie", overview: "", type: .movie)
        old.releaseDate = Calendar.current.date(from: DateComponents(year: 1999, month: 1, day: 1))
        old.searchableText = "old movie"
        context.insert(old)
        let new = MediaItem(id: "2", title: "New Movie", overview: "", type: .movie)
        new.releaseDate = Calendar.current.date(from: DateComponents(year: 2024, month: 1, day: 1))
        new.searchableText = "new movie"
        context.insert(new)
        try context.save()

        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: nil, language: nil, year: "1999")

        XCTAssertEqual(result.totalCount, 1)
        XCTAssertEqual(result.displayed[0].title, "Old Movie")
    }

    @MainActor
    func testEmptyResultForNoMatchingItems() async throws {
        let container = makeContainer()
        let actor = MediaFilterActor(modelContainer: container)

        let result = try await actor.filterAndSort(category: .all, searchText: "nonexistent", sortOrder: .alphabetical, network: nil, language: nil)

        XCTAssertEqual(result.totalCount, 0)
        XCTAssertTrue(result.displayed.isEmpty)
    }

    @MainActor
    func testCategoryCompletedWithStateFilter() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let actor = MediaFilterActor(modelContainer: container)

        let completed = MediaItem(id: "1", title: "Done", overview: "", type: .movie)
        completed.stateValue = "Completed"
        context.insert(completed)
        let active = MediaItem(id: "2", title: "Active", overview: "", type: .movie)
        active.stateValue = "Active"
        context.insert(active)
        try context.save()

        // In completed category, filtering by Active should return 0
        let result = try await actor.filterAndSort(category: .completed, searchText: "", sortOrder: .alphabetical, network: nil, language: nil, state: .active)

        XCTAssertEqual(result.totalCount, 0)
    }
}
