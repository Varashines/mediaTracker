import XCTest
import SwiftData
@testable import MediaTracker

final class PredicateTests: XCTestCase {
    @MainActor
    func makeContainer() -> ModelContainer {
        let schema = Schema([MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    func insertItems(_ items: [MediaItem], into container: ModelContainer) throws {
        let context = container.mainContext
        for item in items {
            context.insert(item)
        }
        try context.save()
    }

    @MainActor
    func testUpcomingPredicate() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildUpcomingPredicate()

        let upcoming = MediaItem(id: "1", title: "Upcoming", overview: "", type: .movie)
        upcoming.storedIsUpcoming = true
        let not = MediaItem(id: "2", title: "Not", overview: "", type: .movie)
        not.storedIsUpcoming = false

        try insertItems([upcoming, not], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Upcoming")
    }

    @MainActor
    func testBasePredicateAllReturnsAll() throws {
        let container = makeContainer()
        // .all falls through to default case without search
        let predicate = MediaFilterPredicates.buildBasePredicate(category: .all, searchToken: "")

        let item1 = MediaItem(id: "1", title: "A", overview: "", type: .movie)
        let item2 = MediaItem(id: "2", title: "B", overview: "", type: .tvShow)

        try insertItems([item1, item2], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 2)
    }

    @MainActor
    func testBasePredicateSearchFilters() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildBasePredicate(category: .all, searchToken: "matrix")

        let matching = MediaItem(id: "1", title: "The Matrix", overview: "")
        matching.searchableText = "the matrix"
        let not = MediaItem(id: "2", title: "Other", overview: "")
        not.searchableText = "other"

        try insertItems([matching, not], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 1)
    }

    @MainActor
    func testFilteredPredicateUpcoming() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildFilteredPredicate(
            category: .upcoming, searchToken: "", stateValue: nil
        )

        let upcoming = MediaItem(id: "1", title: "Upcoming", overview: "", type: .movie)
        upcoming.storedIsUpcoming = true
        let not = MediaItem(id: "2", title: "Not", overview: "", type: .movie)
        not.storedIsUpcoming = false

        try insertItems([upcoming, not], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Upcoming")
    }

    @MainActor
    func testFilteredPredicateCompleted() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildFilteredPredicate(
            category: .completed, searchToken: "", stateValue: nil
        )

        let completed = MediaItem(id: "1", title: "Done", overview: "", type: .movie)
        completed.stateValue = "Completed"
        let active = MediaItem(id: "2", title: "Active", overview: "", type: .movie)
        active.stateValue = "Active"

        try insertItems([completed, active], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Done")
    }

    @MainActor
    func testFilteredPredicateMovieType() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildFilteredPredicate(
            category: .movie, searchToken: "", stateValue: nil
        )

        let movie = MediaItem(id: "1", title: "Movie", overview: "", type: .movie)
        let show = MediaItem(id: "2", title: "Show", overview: "", type: .tvShow)

        try insertItems([movie, show], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Movie")
    }

    @MainActor
    func testFilteredPredicateWithSearchAndState() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildFilteredPredicate(
            category: .all, searchToken: "matrix", stateValue: "Completed"
        )

        let matching = MediaItem(id: "1", title: "The Matrix", overview: "")
        matching.stateValue = "Completed"
        matching.searchableText = "the matrix"
        let wrongState = MediaItem(id: "2", title: "Matrix 2", overview: "")
        wrongState.stateValue = "Active"
        wrongState.searchableText = "matrix 2"

        try insertItems([matching, wrongState], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "1")
    }

    @MainActor
    func testFilteredPredicateWithBadge() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildFilteredPredicate(
            category: .all, searchToken: "", stateValue: nil, badge: "NEW"
        )

        let withBadge = MediaItem(id: "1", title: "New", overview: "", type: .movie)
        withBadge.storedSmartBadgeLabel = "NEW"
        let without = MediaItem(id: "2", title: "Old", overview: "", type: .movie)

        try insertItems([withBadge, without], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "New")
    }

    @MainActor
    func testFilteredPredicateWithLanguage() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildFilteredPredicate(
            category: .all, searchToken: "", stateValue: nil, language: "en"
        )

        let english = MediaItem(id: "1", title: "English", overview: "", type: .movie)
        english.cachedLanguage = "en"
        let french = MediaItem(id: "2", title: "French", overview: "", type: .movie)
        french.cachedLanguage = "fr"

        try insertItems([english, french], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "English")
    }

    @MainActor
    func testManualCollectionPredicate() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildManualCollectionPredicate(
            itemIDs: ["1", "3"], stateValue: nil
        )

        let item1 = MediaItem(id: "1", title: "In Collection", overview: "", type: .movie)
        let item2 = MediaItem(id: "2", title: "Not In", overview: "", type: .movie)
        let item3 = MediaItem(id: "3", title: "Also In", overview: "", type: .movie)

        try insertItems([item1, item2, item3], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0.id == "1" }))
        XCTAssertTrue(result.contains(where: { $0.id == "3" }))
    }

    @MainActor
    func testInProgressPredicate() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildInProgressPredicate()

        let active = MediaItem(id: "1", title: "Active Show", overview: "", type: .tvShow)
        active.stateValue = "Active"
        active.storedIsUpcoming = false
        let wishlist = MediaItem(id: "2", title: "Wishlist", overview: "", type: .tvShow)
        wishlist.stateValue = "Wishlist"

        try insertItems([active, wishlist], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "Active Show")
    }

    @MainActor
    func testBingePredicate() throws {
        let container = makeContainer()
        let predicate = MediaFilterPredicates.buildBingePredicate()

        let binge = MediaItem(id: "1", title: "Binge Show", overview: "", type: .tvShow)
        binge.storedSmartBadgeLabel = "BINGE"
        let drop = MediaItem(id: "2", title: "Drop", overview: "", type: .tvShow)
        drop.storedSmartBadgeLabel = "BINGE DROP"
        let normal = MediaItem(id: "3", title: "Normal", overview: "", type: .tvShow)

        try insertItems([binge, drop, normal], into: container)
        let result = try container.mainContext.fetch(FetchDescriptor<MediaItem>(predicate: predicate))

        XCTAssertEqual(result.count, 2)
    }
}
