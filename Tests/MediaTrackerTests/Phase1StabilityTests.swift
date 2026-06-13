import XCTest
import SwiftData
@testable import MediaTracker

@MainActor
final class Phase1StabilityTests: XCTestCase {
    private func makeContainer() -> ModelContainer {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
            CastMember.self, MediaCollection.self, NetworkEntity.self, GenreEntity.self, LanguageEntity.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - applyStateChange / applyTasteChange

    func testApplyStateChangePersistsAndUpdatesTimestamps() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let before = item.lastUpdated
        item.applyStateChange(.completed)

        XCTAssertEqual(item.state, .completed)
        XCTAssertEqual(item.stateValue, "Completed")
        XCTAssertNotNil(item.lastStateChangeDate)
        XCTAssertNotNil(item.lastUpdated)
        XCTAssertNotEqual(item.lastUpdated, before)
    }

    func testApplyStateChangeIsNoOpWhenUnchanged() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let before = item.lastUpdated
        item.applyStateChange(.wishlist) // already wishlist
        XCTAssertEqual(item.lastUpdated, before)
    }

    func testApplyTasteChangePersists() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        item.applyTasteChange(.love)
        XCTAssertEqual(item.taste, .love)
        XCTAssertEqual(item.tasteValue, "Love")
    }

    // MARK: - softDelete / restoreFromSoftDelete

    func testSoftDeleteHidesItemFromFilters() throws {
        let container = makeContainer()
        let context = container.mainContext
        let activeItem = MediaItem(id: "a", title: "Active", overview: "", type: .movie)
        activeItem.stateValue = "Active"
        context.insert(activeItem)
        let softDeleted = MediaItem(id: "b", title: "Deleted", overview: "", type: .movie)
        softDeleted.stateValue = "Active"
        softDeleted.softDelete()
        context.insert(softDeleted)
        try context.save()

        let predicate = MediaFilterPredicates.buildFilteredPredicate(
            category: .inProgress, searchToken: "", stateValue: nil
        )
        let descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
        let results = try context.fetch(descriptor)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "a")
    }

    func testRestoreFromSoftDeleteMakesItemVisibleAgain() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "a", title: "Test", overview: "", type: .movie)
        item.stateValue = "Active"
        context.insert(item)
        try context.save()

        item.softDelete()
        XCTAssertTrue(item.isSoftDeleted)
        XCTAssertNotNil(item.softDeletedAt)

        item.restoreFromSoftDelete()
        XCTAssertFalse(item.isSoftDeleted)
        XCTAssertNil(item.softDeletedAt)
    }

    func testSoftDeleteIsIdempotent() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "a", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        item.softDelete()
        let firstDate = item.softDeletedAt
        item.softDelete() // no-op
        XCTAssertEqual(item.softDeletedAt, firstDate)
    }

    func testManualCollectionPredicateExcludesSoftDeleted() throws {
        let container = makeContainer()
        let context = container.mainContext

        let coll = MediaCollection(name: "Watched", systemImage: "star")
        context.insert(coll)

        let item = MediaItem(id: "a", title: "Test", overview: "", type: .movie)
        context.insert(item)
        coll.items.append(item)
        try context.save()

        item.softDelete()

        let predicate = MediaFilterPredicates.buildManualCollectionPredicate(
            itemIDs: ["a"], stateValue: nil
        )
        let descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
        let results = try context.fetch(descriptor)
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - MediaThumbnailMetadata versionHash

    func testVersionHashIsStable() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        item.storedProgress = 0.4
        context.insert(item)
        try context.save()

        let m1 = MediaThumbnailMetadata(item: item)
        let m2 = MediaThumbnailMetadata(item: item)
        XCTAssertEqual(m1.versionHash, m2.versionHash)
        XCTAssertTrue(m1.versionHash.contains("0.4"))
    }

    func testVersionHashChangesWithProgress() throws {
        let container = makeContainer()
        let context = container.mainContext
        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let before = MediaThumbnailMetadata(item: item)
        item.storedProgress = 0.7
        let after = MediaThumbnailMetadata(item: item)
        XCTAssertNotEqual(before.versionHash, after.versionHash)
    }
}
