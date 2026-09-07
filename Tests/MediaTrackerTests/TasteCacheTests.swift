import XCTest
import SwiftData
@testable import MediaTracker

final class TasteCacheTests: MTTestCase {

    @MainActor
    private func makeContainer() -> ModelContainer {
        let schema = Schema([
            MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
            SeasonCastMember.self, CastMember.self, PersonImageEntity.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.cachedForYouPicks.rawValue)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.tasteVersion.rawValue)
        await MainActor.run {
            TasteActor.clearCache()
        }
        try await super.tearDown()
    }

    @MainActor
    func testClearCacheDoesNotWipeDiskCache() throws {
        // Seed mock persisted payload in UserDefaults
        let testPicks = [TasteActor.PersistedRecommendation(itemID: "m1", reason: "Because you love Sci-Fi")]
        let payload = TasteActor.PersistedPicksPayload(picks: testPicks, timestamp: Date(), tasteVersion: 1)
        let data = try JSONEncoder().encode(payload)
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.cachedForYouPicks.rawValue)

        // Clear in-memory cache
        TasteActor.clearCache()

        // Disk cache should still be intact
        let retrieved = UserDefaults.standard.data(forKey: UserDefaultsKeys.cachedForYouPicks.rawValue)
        XCTAssertNotNil(retrieved, "clearCache() must not remove cached_for_you_picks from UserDefaults")
    }

    @MainActor
    func testDiskCacheRestoresRecommendationsWhenMemoryCleared() async throws {
        let container = makeContainer()
        let context = container.mainContext

        // Create a media item matching the persisted pick
        let item = MediaItem(id: "m42", title: "Interstellar", overview: "Space exploration", type: .movie)
        item.stateValue = MediaState.wishlistRaw
        item.tasteValue = TasteValue.none.rawValue
        item.cachedGenres = ["Science Fiction"]
        item.releaseDate = Date().addingTimeInterval(-100_000)
        context.insert(item)
        try context.save()

        let testPicks = [TasteActor.PersistedRecommendation(itemID: "m42", reason: "Top Sci-Fi Pick")]
        let payload = TasteActor.PersistedPicksPayload(picks: testPicks, timestamp: Date(), tasteVersion: 0)
        let data = try JSONEncoder().encode(payload)
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.cachedForYouPicks.rawValue)

        // Clear memory cache so it's forced to read disk
        TasteActor.clearCache()

        let actor = TasteActor(modelContainer: container)
        let recs = await actor.calculateRecommendations(forceRefresh: false)

        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs.first?.itemID, "m42")
        XCTAssertEqual(recs.first?.reason, "Top Sci-Fi Pick")
    }

    @MainActor
    func testStaleDiskCacheReturnsImmediatelyAndTriggersRecompute() async throws {
        let container = makeContainer()
        let context = container.mainContext

        let item = MediaItem(id: "m42", title: "Interstellar", overview: "Space exploration", type: .movie)
        item.stateValue = MediaState.wishlistRaw
        item.tasteValue = TasteValue.none.rawValue
        item.cachedGenres = ["Science Fiction"]
        item.releaseDate = Date().addingTimeInterval(-100_000)
        context.insert(item)
        try context.save()

        // Set stale taste version on disk (version 0 vs current version 1)
        UserDefaults.standard.set(1, forKey: UserDefaultsKeys.tasteVersion.rawValue)
        let testPicks = [TasteActor.PersistedRecommendation(itemID: "m42", reason: "Stale Pick")]
        let payload = TasteActor.PersistedPicksPayload(picks: testPicks, timestamp: Date(), tasteVersion: 0)
        let data = try JSONEncoder().encode(payload)
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.cachedForYouPicks.rawValue)

        TasteActor.clearCache()

        let initialRefreshCount = MediaStateService.shared.recommendationsRefreshedCount

        let actor = TasteActor(modelContainer: container)
        // Stale disk cache should return immediately for 0ms cold start
        let recs = await actor.calculateRecommendations(forceRefresh: false)
        XCTAssertEqual(recs.count, 1)
        XCTAssertEqual(recs.first?.reason, "Stale Pick")

        // Wait a moment for background Task.detached to complete and notify
        for _ in 0..<20 {
            if MediaStateService.shared.recommendationsRefreshedCount > initialRefreshCount {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }

        XCTAssertGreaterThan(MediaStateService.shared.recommendationsRefreshedCount, initialRefreshCount,
                             "Background recompute should post recommendationsRefreshed when stale")
    }
}
