import XCTest
import SwiftData
@testable import MediaTracker

final class SyncCoordinatorTests: XCTestCase {
    func testSyncCoordinatorDeduplicates() async throws {
        let coordinator = SyncCoordinator.shared
        let opStarted = XCTestExpectation(description: "Operation started")

        // Task 1: calls coordinator.perform — registers the task in inFlightTasks
        let task1 = Task {
            try await coordinator.perform(key: "dedup_key") {
                opStarted.fulfill()
                try await Task.sleep(nanoseconds: 200_000_000)
                return "result1"
            }
        }

        // Wait until task1's operation is actually running (registered in the actor)
        await fulfillment(of: [opStarted], timeout: 1.0)
        // Small delay to ensure the actor has stored the task reference
        try await Task.sleep(nanoseconds: 10_000_000)

        // Task 2: finds the existing task in inFlightTasks and deduplicates
        let task2 = Task {
            try await coordinator.perform(key: "dedup_key") {
                return "result2"
            }
        }

        let result1 = try await task1.value
        let result2 = try await task2.value

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
