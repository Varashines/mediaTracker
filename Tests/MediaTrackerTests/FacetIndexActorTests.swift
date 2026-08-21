import XCTest
import SwiftData
@testable import MediaTracker

final class FacetIndexActorTests: XCTestCase {
    func testRebuildCreatesNormalizedUniqueFacetEntries() async throws {
        let schema = Schema([MediaItem.self, MediaFacetIndex.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = MediaItem(id: "movie_1", title: "Facet Test", overview: "", type: .movie)
        item.cachedGenres = ["Action", "action", " Science Fiction "]
        item.cachedWatchProviders = ["Netflix", "Netflix"]
        item.cachedNetwork = "HBO,  Max"
        context.insert(item)
        try context.save()

        let actor = FacetIndexActor.shared(modelContainer: container)
        let result = try await actor.rebuild()

        XCTAssertEqual(result.indexedItems, 1)
        XCTAssertEqual(result.insertedEntries, 5)
        XCTAssertEqual(result.removedEntries, 0)

        let entries = try context.fetch(FetchDescriptor<MediaFacetIndex>())
        XCTAssertEqual(
            Set(entries.map(\.id)),
            [
                "movie_1|genre|action",
                "movie_1|genre|science fiction",
                "movie_1|provider|netflix",
                "movie_1|network|hbo",
                "movie_1|network|max"
            ]
        )
    }

    func testRebuildRemovesStaleFacetEntries() async throws {
        let schema = Schema([MediaItem.self, MediaFacetIndex.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = MediaItem(id: "show_1", title: "Facet Test", overview: "", type: .tvShow)
        item.cachedGenres = ["Drama"]
        context.insert(item)
        try context.save()

        let actor = FacetIndexActor.shared(modelContainer: container)
        _ = try await actor.rebuild()

        item.cachedGenres = ["Comedy"]
        try context.save()
        let result = try await actor.rebuild()

        XCTAssertEqual(result.insertedEntries, 1)
        XCTAssertEqual(result.removedEntries, 1)

        let entries = try context.fetch(FetchDescriptor<MediaFacetIndex>())
        XCTAssertEqual(entries.map(\.id), ["show_1|genre|comedy"])
    }
}
