import XCTest
import SwiftData
@testable import MediaTracker

@MainActor
final class Phase4ArchitectureTests: XCTestCase {
    private func makeContainer() -> ModelContainer {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
            CastMember.self, MediaCollection.self, NetworkEntity.self, GenreEntity.self, LanguageEntity.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    func testApplyUpdateReplacesInAllLists() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "a", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let cache = DisplayCache()
        let initial = MediaThumbnailMetadata(item: item)
        cache.displayedItems = [initial]
        cache.recentlyAddedItems = [initial]
        cache.homeContinueWatchingItems = [initial]
        cache.featuredUpcomingItems = [initial]
        cache.spotlightHero = initial
        cache.groupedItems = [("Group", [initial])]
        cache.pickOfTheDay = [initial]
        cache.recommendations = [initial]

        // Mutate and rebuild metadata.
        item.state = .completed
        item.syncCachedProperties()
        let updated = MediaThumbnailMetadata(item: item)

        cache.applyUpdate(updated, id: item.persistentModelID, animated: false)

        XCTAssertEqual(cache.displayedItems.first?.state, .completed)
        XCTAssertEqual(cache.recentlyAddedItems.first?.state, .completed)
        XCTAssertEqual(cache.homeContinueWatchingItems.first?.state, .completed)
        XCTAssertEqual(cache.featuredUpcomingItems.first?.state, .completed)
        XCTAssertEqual(cache.spotlightHero?.state, .completed)
        XCTAssertEqual(cache.groupedItems.first?.1.first?.state, .completed)
        XCTAssertEqual(cache.pickOfTheDay.first?.state, .completed)
        XCTAssertEqual(cache.recommendations.first?.state, .completed)
    }

    func testApplyUpdateRemovesFromAllListsWhenNil() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "a", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let cache = DisplayCache()
        let m = MediaThumbnailMetadata(item: item)
        cache.displayedItems = [m]
        cache.recentlyAddedItems = [m]
        cache.featuredUpcomingItems = [m]
        cache.groupedItems = [("G", [m])]
        cache.spotlightHero = m

        cache.applyUpdate(nil, id: item.persistentModelID, animated: false)

        XCTAssertTrue(cache.displayedItems.isEmpty)
        XCTAssertTrue(cache.recentlyAddedItems.isEmpty)
        XCTAssertTrue(cache.featuredUpcomingItems.isEmpty)
        XCTAssertTrue(cache.groupedItems.first?.1.isEmpty ?? false)
        XCTAssertNil(cache.spotlightHero)
    }

    func testApplyUpdateIsNoopForUnknownID() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "a", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let cache = DisplayCache()
        let m = MediaThumbnailMetadata(item: item)
        cache.displayedItems = [m]

        // Build a metadata for a different (non-existent) item.
        let ghost = MediaItem(id: "ghost", title: "G", overview: "", type: .movie)
        let ghostMeta = MediaThumbnailMetadata(item: ghost)
        cache.applyUpdate(ghostMeta, id: ghost.persistentModelID, animated: false)

        // Original list is untouched.
        XCTAssertEqual(cache.displayedItems.count, 1)
        XCTAssertEqual(cache.displayedItems.first?.itemID, "a")
    }

}
