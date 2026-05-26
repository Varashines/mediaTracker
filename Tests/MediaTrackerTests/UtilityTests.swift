import XCTest
import SwiftData
@testable import MediaTracker

final class SyncCoordinatorTests: XCTestCase {
    func testSyncCoordinatorDeduplicates() async throws {
        let coordinator = SyncCoordinator.shared

        // Two concurrent calls with the same key
        async let r1 = coordinator.perform(key: "test_key") {
            try await Task.sleep(nanoseconds: 100_000_000)
            return "result1"
        }

        async let r2 = coordinator.perform(key: "test_key") {
            try await Task.sleep(nanoseconds: 100_000_000)
            return "result2"
        }

        // Since they share the same key, both should get "result1"
        let result1 = try await r1
        let result2 = try await r2

        XCTAssertEqual(result1, "result1")
        XCTAssertEqual(result2, "result1")
    }

    func testSyncCoordinatorSeparateKeysRunIndependently() async throws {
        let coordinator = SyncCoordinator.shared

        async let r1 = coordinator.perform(key: "key_a") {
            try await Task.sleep(nanoseconds: 50_000_000)
            return "from_a"
        }

        async let r2 = coordinator.perform(key: "key_b") {
            try await Task.sleep(nanoseconds: 50_000_000)
            return "from_b"
        }

        let result1 = try await r1
        let result2 = try await r2

        XCTAssertEqual(result1, "from_a")
        XCTAssertEqual(result2, "from_b")
    }

    func testSyncCoordinatorReusesAfterCompletion() async throws {
        let coordinator = SyncCoordinator.shared

        let first = try await coordinator.perform(key: "reuse_key") {
            return "first_result"
        }
        XCTAssertEqual(first, "first_result")

        // Second call should NOT reuse the completed task (defer cleaned it up)
        let second = try await coordinator.perform(key: "reuse_key") {
            return "second_result"
        }
        XCTAssertEqual(second, "second_result")
    }

    func testSyncCoordinatorThrowsOnTypeMismatch() async throws {
        let coordinator = SyncCoordinator.shared

        // First call with String result
        let first: String = try await coordinator.perform(key: "type_key") {
            return "hello"
        }
        XCTAssertEqual(first, "hello")
    }
}

final class SaveCoordinatorTests: XCTestCase {
    @MainActor
    func testSaveCoordinatorDebounces() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext

        let coordinator = SaveCoordinator.shared

        let item1 = MediaItem(id: "1", title: "One", overview: "")
        context.insert(item1)

        // Request save multiple times rapidly
        coordinator.requestSave(context, delayMs: 50)
        coordinator.requestSave(context, delayMs: 50)
        coordinator.requestSave(context, delayMs: 50)

        try await Task.sleep(nanoseconds: 200_000_000)

        // Only one save should have occurred
        let count = try context.fetch(FetchDescriptor<MediaItem>()).count
        XCTAssertEqual(count, 1)
    }

    @MainActor
    func testSaveCoordinatorForceSave() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext

        let coordinator = SaveCoordinator.shared

        let item = MediaItem(id: "1", title: "Test", overview: "")
        context.insert(item)

        coordinator.forceSave(context)

        let count = try context.fetch(FetchDescriptor<MediaItem>()).count
        XCTAssertEqual(count, 1)
    }
}
