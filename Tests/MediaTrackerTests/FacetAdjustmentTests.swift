import XCTest
import SwiftData
@testable import MediaTracker

/// Regression tests for the shared facet-count helper (`adjustFacets`) exercised
/// through the public incremental `updateItemAdded` / `updateItemDeleted` paths.
final class FacetAdjustmentTests: MTTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self,
            StudioAliasEntity.self, NetworkEntity.self, GenreEntity.self,
            LanguageEntity.self, BadgeEntity.self, ProviderEntity.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Stub the image session so the trailing `extractMissingColors` call inside
    /// `updateItemAdded` never touches the real network.
    @MainActor
    private func stubImageSession() {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        ImageCache.shared.configureForTesting(session: URLSession(configuration: sessionConfig))
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotLoadFromNetwork)
        }
    }

    @MainActor
    private func restoreImageSession() {
        MockURLProtocol.requestHandler = nil
        ImageCache.shared.configureForTesting()
    }

    @MainActor
    private func makeSyncService() throws -> (ModelContainer, ModelContext, DiscoverySyncService) {
        let container = try makeContainer()
        let context = container.mainContext
        return (container, context, DiscoverySyncService(modelContainer: container))
    }

    // MARK: - Add populates every facet kind exactly once

    @MainActor
    func testUpdateItemAddedPopulatesAllFacetKinds() async throws {
        stubImageSession()
        defer { restoreImageSession() }

        let (_, context, sync) = try makeSyncService()

        let item = MediaItem(id: "m1", title: "Faceted Movie", overview: "", type: .movie)
        item.cachedNetwork = "Netflix"
        item.cachedGenres = ["Drama", "Comedy"]
        item.cachedLanguage = "en"
        item.storedSmartBadgeLabel = "PREMIERE"
        item.cachedWatchProviders = ["Netflix", "Disney+"]
        item.cachedWatchProviderLogoPaths = ["/netflix.png", ""]
        context.insert(item)
        try context.save()

        await sync.updateItemAdded(item.persistentModelID)

        XCTAssertEqual(try context.fetch(FetchDescriptor<NetworkEntity>()).first(where: { $0.name == "Netflix" })?.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GenreEntity>()).first(where: { $0.name == "Drama" })?.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<GenreEntity>()).first(where: { $0.name == "Comedy" })?.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<LanguageEntity>()).first(where: { $0.code == "en" })?.count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<BadgeEntity>()).first(where: { $0.label == "PREMIERE" })?.count, 1)

        // Providers: logo backfilled when present, nil when path empty.
        let netflixProvider = try context.fetch(FetchDescriptor<ProviderEntity>()).first(where: { $0.name == "Netflix" })
        XCTAssertEqual(netflixProvider?.count, 1)
        XCTAssertEqual(netflixProvider?.logoPath, "/netflix.png")
        let disneyProvider = try context.fetch(FetchDescriptor<ProviderEntity>()).first(where: { $0.name == "Disney+" })
        XCTAssertEqual(disneyProvider?.count, 1)
        XCTAssertNil(disneyProvider?.logoPath)
    }

    // MARK: - Repeat adds increment without duplicate rows

    @MainActor
    func testRepeatAddIncrementsWithoutDuplicateRows() async throws {
        stubImageSession()
        defer { restoreImageSession() }

        let (_, context, sync) = try makeSyncService()

        for id in ["a", "b"] {
            let item = MediaItem(id: id, title: "Show \(id)", overview: "", type: .tvShow)
            item.cachedNetwork = "HBO"
            item.cachedGenres = ["Crime"]
            item.cachedLanguage = "en"
            context.insert(item)
        }
        try context.save()

        for objectID in try context.fetch(FetchDescriptor<MediaItem>()) {
            await sync.updateItemAdded(objectID.persistentModelID)
        }

        let networks = try context.fetch(FetchDescriptor<NetworkEntity>())
        XCTAssertEqual(networks.count, 1, "Only one NetworkEntity row should exist")
        XCTAssertEqual(networks.first?.count, 2, "Two items should increment count to 2")

        let genres = try context.fetch(FetchDescriptor<GenreEntity>())
        XCTAssertEqual(genres.count, 1)
        XCTAssertEqual(genres.first?.count, 2)
    }

    // MARK: - Delete removes at zero, decrements otherwise

    @MainActor
    func testDeleteDecremementsAndDeletesAtZero() async throws {
        stubImageSession()
        defer { restoreImageSession() }

        let (_, context, sync) = try makeSyncService()

        func addItem(_ id: String) throws -> MediaItem {
            let item = MediaItem(id: id, title: "Item \(id)", overview: "", type: .movie)
            item.cachedNetwork = "Apple TV+"
            item.cachedGenres = ["Sci-Fi"]
            item.cachedLanguage = "ja"
            item.storedSmartBadgeLabel = "FINALE"
            item.cachedWatchProviders = ["Apple TV+"]
            context.insert(item)
            return item
        }

        let first = try addItem("d1")
        _ = try addItem("d2")
        try context.save()

        for objectID in try context.fetch(FetchDescriptor<MediaItem>()) {
            await sync.updateItemAdded(objectID.persistentModelID)
        }

        // Sanity: counts are 2 before any deletes.
        XCTAssertEqual(try context.fetch(FetchDescriptor<NetworkEntity>()).first?.count, 2)

        // First delete decrements but keeps entities alive.
        await sync.updateItemDeleted(
            network: first.cachedNetwork,
            genres: first.cachedGenres,
            language: first.cachedLanguage,
            badge: first.storedSmartBadgeLabel,
            providers: first.cachedWatchProviders
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<NetworkEntity>()).first?.count, 1, "Count should decrement to 1 without deleting")
        XCTAssertNotNil(try context.fetch(FetchDescriptor<NetworkEntity>()).first)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<GenreEntity>()).first)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<LanguageEntity>()).first)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<BadgeEntity>()).first)
        XCTAssertNotNil(try context.fetch(FetchDescriptor<ProviderEntity>()).first)

        // Second delete drives every count to zero → rows removed.
        await sync.updateItemDeleted(
            network: first.cachedNetwork,
            genres: first.cachedGenres,
            language: first.cachedLanguage,
            badge: first.storedSmartBadgeLabel,
            providers: first.cachedWatchProviders
        )
        XCTAssertTrue(try context.fetch(FetchDescriptor<NetworkEntity>()).isEmpty, "NetworkEntity should be deleted at count <= 0")
        XCTAssertTrue(try context.fetch(FetchDescriptor<GenreEntity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LanguageEntity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BadgeEntity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProviderEntity>()).isEmpty)
    }

    // MARK: - Deleting with no matching entity never creates rows

    @MainActor
    func testDeleteWithoutExistingEntitiesCreatesNothing() async throws {
        stubImageSession()
        defer { restoreImageSession() }

        let (_, context, sync) = try makeSyncService()

        await sync.updateItemDeleted(
            network: "Phantom Network",
            genres: ["Phantom Genre"],
            language: "xx",
            badge: "PHANTOM",
            providers: ["Phantom Provider"]
        )

        XCTAssertTrue(try context.fetch(FetchDescriptor<NetworkEntity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<GenreEntity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<LanguageEntity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<BadgeEntity>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<ProviderEntity>()).isEmpty)
    }
}
