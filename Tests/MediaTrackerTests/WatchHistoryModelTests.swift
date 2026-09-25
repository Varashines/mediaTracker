import XCTest
import SwiftData
@testable import MediaTracker

@MainActor
final class WatchHistoryModelTests: MTTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([WatchCycle.self, WatchEvent.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    func testCyclePersistsTypedState() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cycle = WatchCycle(
            mediaID: "movie_1",
            kind: .movie,
            state: .active
        )
        context.insert(cycle)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<WatchCycle>()).first
        XCTAssertEqual(fetched?.mediaID, "movie_1")
        XCTAssertEqual(fetched?.kind, .movie)
        XCTAssertEqual(fetched?.state, .active)
    }

    func testPersistentStoreSchemaUpgradePreservesExistingMedia() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchHistoryMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")

        do {
            let oldSchema = Schema([MediaItem.self, MovieDetails.self])
            let oldConfiguration = ModelConfiguration(schema: oldSchema, url: storeURL)
            let oldContainer = try ModelContainer(for: oldSchema, configurations: [oldConfiguration])
            let oldContext = oldContainer.mainContext
            let item = MediaItem(id: "movie_existing", title: "Existing Movie", overview: "", type: .movie)
            item.stateValue = MediaState.completed.rawValue
            oldContext.insert(item)
            try oldContext.save()
        }

        let newSchema = Schema([MediaItem.self, MovieDetails.self, WatchCycle.self, WatchEvent.self])
        let newConfiguration = ModelConfiguration(schema: newSchema, url: storeURL)
        let upgradedContainer = try ModelContainer(for: newSchema, configurations: [newConfiguration])
        let items = try upgradedContainer.mainContext.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.id, "movie_existing")
        XCTAssertEqual(items.first?.title, "Existing Movie")
        XCTAssertEqual(items.first?.state, .completed)
    }

    func testEventDefaultsToActiveAndCanBeVoided() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cycleID = UUID()
        let event = WatchEvent(
            cycleID: cycleID,
            mediaID: "tv_1",
            episodeID: "tv_1_1_1",
            source: .automatic,
            deduplicationKey: "tv_1:1:1:manual"
        )
        context.insert(event)
        try context.save()

        XCTAssertTrue(event.isActive)
        event.voidedAt = Date()
        XCTAssertFalse(event.isActive)
    }

    func testRemapHistoryKeepsCyclesAndEventsAttachedToNewID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cycle = WatchCycle(mediaID: "123", kind: .movie, state: .completed, isComplete: true)
        context.insert(cycle)
        context.insert(WatchEvent(
            cycleID: cycle.id,
            mediaID: "123",
            watchedAt: Date(),
            deduplicationKey: "remap"
        ))
        try context.save()

        WatchHistoryCoordinator.remapHistory(from: "123", to: "movie_123", context: context)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchCycle>()).first?.mediaID, "movie_123")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchEvent>()).first?.mediaID, "movie_123")
    }

    func testSummaryCountsTitleCyclesWithoutEpisodeEvents() {
        let cycles = [
            WatchCycle(mediaID: "tv_1", kind: .tvShow, state: .completed, isComplete: true),
            WatchCycle(mediaID: "tv_1", kind: .tvShow, state: .completed, isRewatch: true, isComplete: true),
            WatchCycle(mediaID: "tv_1", kind: .tvShow, state: .active, isRewatch: true),
            WatchCycle(mediaID: "tv_1", kind: .tvShow, state: .paused, isRewatch: true)
        ]

        let summary = WatchHistorySummary(cycles: cycles)

        XCTAssertEqual(summary.cycleCount, 4)
        XCTAssertEqual(summary.completedCycleCount, 2)
        XCTAssertEqual(summary.completedRewatchCount, 1)
        XCTAssertEqual(summary.activeRewatchCount, 1)
        XCTAssertEqual(summary.pausedRewatchCount, 1)
    }

    func testLibraryStatsAggregatesCompletedRewatchesByTitle() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            SeasonCastMember.self, TVEpisode.self, CastMember.self,
            MediaCollection.self, StudioAliasEntity.self, WatchCycle.self, WatchEvent.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let first = MediaItem(id: "movie_1", title: "First", overview: "", type: .movie)
        let second = MediaItem(id: "movie_2", title: "Second", overview: "", type: .movie)
        context.insert(first)
        context.insert(second)
        context.insert(WatchCycle(mediaID: first.id, kind: .movie, state: .completed, isRewatch: true))
        context.insert(WatchCycle(mediaID: first.id, kind: .movie, state: .completed, isRewatch: true))
        context.insert(WatchCycle(mediaID: second.id, kind: .movie, state: .active, isRewatch: true))
        try context.save()

        LibraryStatsActor.clearCache()
        let stats = try await LibraryStatsActor(modelContainer: container).fetchStats(includeCinephileData: false)

        XCTAssertEqual(stats.totalRewatches, 2)
        XCTAssertEqual(stats.titlesRewatched, 1)
        XCTAssertEqual(stats.partialRewatches, 1)
    }
}
