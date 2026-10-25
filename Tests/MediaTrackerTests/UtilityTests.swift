import XCTest
import SwiftData
@testable import MediaTracker

final class SaveCoordinatorTests: MTTestCase {
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

    /// A change made inside the 350 ms debounce window must still reach disk when the
    /// app quits. Autosave is disabled, so without `flushAll()` nothing would save it.
    @MainActor
    func testFlushAllPersistsPendingDebouncedSave() throws {
        let container = try ModelContainer(
            for: MediaItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(MediaItem(id: "1", title: "Quit Fast", overview: ""))

        // A debounce far longer than the test: only flushAll() can save this.
        SaveCoordinator.shared.requestSave(context, delayMs: 600_000)
        XCTAssertTrue(context.hasChanges, "insert is still only in memory")

        SaveCoordinator.shared.flushAll()

        XCTAssertFalse(context.hasChanges, "flushAll must persist the pending change")
        let stored = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.title, "Quit Fast")
    }

    @MainActor
    func testFlushAllWithNothingPendingIsHarmless() {
        SaveCoordinator.shared.flushAll()
        SaveCoordinator.shared.flushAll()
        XCTAssertTrue(true, "must not trap with an empty queue")
    }
}

@MainActor
final class SleepManagerTests: MTTestCase {
    func testSleepAssertionLifecycle() {
        let sleepManager = SleepManager.shared
        XCTAssertFalse(sleepManager.isSleepBlocked)

        let assertion = sleepManager.beginPreventingSleep(reason: "Unit Test Import")
        XCTAssertTrue(sleepManager.isSleepBlocked)
        XCTAssertFalse(sleepManager.isAsleep)

        sleepManager.forceSleep()
        XCTAssertFalse(sleepManager.isAsleep, "forceSleep must be ignored while sleep assertions are active")

        sleepManager.endPreventingSleep(id: assertion)
        XCTAssertFalse(sleepManager.isSleepBlocked)
    }
}
