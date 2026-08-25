import XCTest
import SwiftData
@testable import MediaTracker

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

@MainActor
final class SleepManagerTests: XCTestCase {
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
