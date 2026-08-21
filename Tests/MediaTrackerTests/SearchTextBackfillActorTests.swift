import XCTest
import SwiftData
@testable import MediaTracker

final class SearchTextBackfillActorTests: XCTestCase {
    func testRebuildAddsProvidersToExistingSearchableText() async throws {
        let schema = Schema([MediaItem.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let item = MediaItem(id: "provider_search", title: "Provider Search", overview: "", type: .movie)
        item.cachedWatchProviders = ["Netflix"]
        item.searchableText = "provider search"
        context.insert(item)
        try context.save()

        let actor = SearchTextBackfillActor.shared(modelContainer: container)
        let result = try await actor.rebuild()

        XCTAssertEqual(result.updatedItems, 1)
        XCTAssertFalse(result.unchanged)

        let refreshedItems = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertTrue(refreshedItems.first?.searchableText.contains("netflix") == true)
    }
}
