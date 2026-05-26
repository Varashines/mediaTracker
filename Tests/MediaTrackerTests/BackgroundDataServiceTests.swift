import XCTest
import SwiftData
@testable import MediaTracker

final class BackgroundDataServiceTests: XCTestCase {
    @MainActor
    func makeContainer() -> ModelContainer {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self, NetworkEntity.self, GenreEntity.self, LanguageEntity.self, BadgeEntity.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    func testCreateNewMovieItem() async throws {
        let container = makeContainer()
        let service = BackgroundDataService(modelContainer: container)

        let (id, isExisting) = await service.createNewMediaItem(
            uniqueID: "movie_1",
            tmdbID: 1,
            type: .movie,
            title: "Test Movie",
            overview: "A test movie",
            posterURL: nil,
            releaseDateString: "2026-05-01"
        )

        XCTAssertNotNil(id)
        XCTAssertFalse(isExisting)

        // Verify item was created with correct properties
        let context = container.mainContext
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == "movie_1" })
        let items = try context.fetch(descriptor)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Test Movie")
        XCTAssertEqual(items.first?.type, .movie)
    }

    @MainActor
    func testCreateNewTVShowItem() async throws {
        let container = makeContainer()
        let service = BackgroundDataService(modelContainer: container)

        let (id, isExisting) = await service.createNewMediaItem(
            uniqueID: "tv_1",
            tmdbID: 1,
            type: .tvShow,
            title: "Test Show",
            overview: "A test show",
            posterURL: nil,
            releaseDateString: nil
        )

        XCTAssertNotNil(id)
        XCTAssertFalse(isExisting)
        let tvCount = try container.mainContext.fetch(FetchDescriptor<MediaItem>()).count
        XCTAssertEqual(tvCount, 1)
    }

    @MainActor
    func testCreateDuplicateItemReturnsExisting() async throws {
        let container = makeContainer()
        let service = BackgroundDataService(modelContainer: container)

        let (id1, _) = await service.createNewMediaItem(
            uniqueID: "movie_1",
            tmdbID: 1,
            type: .movie,
            title: "First",
            overview: "",
            posterURL: nil,
            releaseDateString: nil
        )

        let (id2, isExisting2) = await service.createNewMediaItem(
            uniqueID: "movie_1",
            tmdbID: 1,
            type: .movie,
            title: "Duplicate",
            overview: "",
            posterURL: nil,
            releaseDateString: nil
        )

        XCTAssertEqual(id1, id2)
        XCTAssertTrue(isExisting2)
        let count = try container.mainContext.fetch(FetchDescriptor<MediaItem>()).count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testDeleteMediaItem() async throws {
        let container = makeContainer()
        let context = container.mainContext
        let service = BackgroundDataService(modelContainer: container)

        let item = MediaItem(id: "delete_me", title: "To Delete", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        let preDelete = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(preDelete.count, 1)

        await service.deleteMediaItem(id: "delete_me")

        // Verify deletion (may be async)
        let remaining = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertTrue(remaining.isEmpty || remaining.allSatisfy { $0.id != "delete_me" })
    }

    @MainActor
    func testDeleteNonexistentItemDoesNotCrash() async throws {
        let container = makeContainer()
        let service = BackgroundDataService(modelContainer: container)

        // Should not throw or crash
        await service.deleteMediaItem(id: "nonexistent")
    }
}
