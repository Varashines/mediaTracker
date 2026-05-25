import XCTest
import SwiftData
@testable import MediaTracker

final class DiscoverySyncServiceTests: XCTestCase {
    @MainActor
    func testNetworkCountDeduplication() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self,
            StudioAliasEntity.self, NetworkEntity.self, GenreEntity.self, LanguageEntity.self, BadgeEntity.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Create Studio Alias rule: Both "Walt Disney Pictures" and "Walt Disney Animation Studios" map to "Walt Disney Animation Studios"
        let alias = StudioAliasEntity(
            target: "Walt Disney Animation Studios",
            sources: ["Walt Disney Pictures", "Walt Disney Animation Studios"],
            preferredLogoSource: "Walt Disney Animation Studios"
        )
        context.insert(alias)

        // Create a MediaItem with both names in the cachedNetwork
        let item = MediaItem(id: "1", title: "Test Movie", overview: "Test", type: .movie)
        item.cachedNetwork = "Walt Disney Animation Studios, Walt Disney Pictures"
        item.cachedNetworkLogoPath = "/logo1.png,/logo2.png"
        context.insert(item)

        try context.save()

        // Initialize sync service
        let syncService = DiscoverySyncService(modelContainer: container)

        // Run sync
        await syncService.syncLibrary(force: true)

        // Verify the count of the target network is exactly 1 (not 2)
        let descriptor = FetchDescriptor<NetworkEntity>()
        let networks = try context.fetch(descriptor)
        
        let disneyNetwork = networks.first(where: { $0.name == "Walt Disney Animation Studios" })
        XCTAssertNotNil(disneyNetwork, "NetworkEntity for 'Walt Disney Animation Studios' should have been created.")
        XCTAssertEqual(disneyNetwork?.count, 1, "Count should be exactly 1 due to deduplication (was double-counted as 2).")
        XCTAssertEqual(disneyNetwork?.sourceNames.sorted(), ["Walt Disney Animation Studios", "Walt Disney Pictures"], "All original names should be accumulated.")
    }

    @MainActor
    func testIncrementalItemAddAndRemoveDeduplication() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self,
            StudioAliasEntity.self, NetworkEntity.self, GenreEntity.self, LanguageEntity.self, BadgeEntity.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // Create Studio Alias rule: Both "Walt Disney Pictures" and "Walt Disney Animation Studios" map to "Walt Disney Animation Studios"
        let alias = StudioAliasEntity(
            target: "Walt Disney Animation Studios",
            sources: ["Walt Disney Pictures", "Walt Disney Animation Studios"],
            preferredLogoSource: "Walt Disney Animation Studios"
        )
        context.insert(alias)

        // Create a NetworkEntity beforehand with count 0
        let disneyNetwork = NetworkEntity(name: "Walt Disney Animation Studios", count: 0)
        context.insert(disneyNetwork)
        try context.save()

        // Create a MediaItem with both names in the cachedNetwork
        let item = MediaItem(id: "2", title: "Incremental Movie", overview: "Test", type: .movie)
        item.cachedNetwork = "Walt Disney Animation Studios, Walt Disney Pictures"
        context.insert(item)
        try context.save()

        let syncService = DiscoverySyncService(modelContainer: container)

        // Test incremental add
        await syncService.updateItemAdded(item.persistentModelID)

        let networksAfterAdd = try context.fetch(FetchDescriptor<NetworkEntity>())
        let disneyAfterAdd = networksAfterAdd.first(where: { $0.name == "Walt Disney Animation Studios" })
        XCTAssertEqual(disneyAfterAdd?.count, 1, "Incremental add should only increment count by 1 (deduplicated).")

        // Test incremental delete
        await syncService.updateItemDeleted(
            network: item.cachedNetwork,
            genres: [],
            language: nil,
            badge: nil
        )

        let networksAfterDelete = try context.fetch(FetchDescriptor<NetworkEntity>())
        let disneyAfterDelete = networksAfterDelete.first(where: { $0.name == "Walt Disney Animation Studios" })
        
        // Note: updateItemDeleted will delete the entity if its count <= 0
        XCTAssert(disneyAfterDelete == nil || (disneyAfterDelete?.count ?? 0) <= 0, "Incremental delete should only decrement count by 1 (resulting in <= 0 and possibly deleted).")
    }
}
