import XCTest
@testable import MediaTracker

@MainActor
final class AppErrorStateTests: XCTestCase {
    private var state: AppErrorState { .shared }

    override func setUp() {
        state.dismissCurrentToast()
    }

    override func tearDown() {
        state.dismissCurrentToast()
    }

    func testSecondToastQueuesBehindVisibleOne() async throws {
        state.showToast("First", style: .info, duration: 5)
        XCTAssertEqual(state.currentToast?.message, "First")

        state.showToast("Second", style: .success, duration: 5)
        // First stays visible; second is queued, not shown yet.
        XCTAssertEqual(state.currentToast?.message, "First")

        state.dismissCurrentToast()
        // advanceToNextToast schedules the next presentation after a short beat.
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(state.currentToast?.message, "Second")
    }

    func testDuplicateMessageDoesNotRestartOrQueue() async throws {
        state.showToast("Same", style: .warning, duration: 5)
        state.showToast("Same", style: .warning, duration: 5)
        XCTAssertEqual(state.currentToast?.message, "Same")
        state.dismissCurrentToast()
        try await Task.sleep(for: .milliseconds(300))
        // Nothing queued — the duplicate was suppressed.
        XCTAssertNil(state.currentToast)
    }

    func testAutoDismissAdvancesToQueuedToast() async throws {
        state.showToast("Auto", style: .info, duration: 0.05)
        state.showToast("Next", style: .info, duration: 5)
        XCTAssertEqual(state.currentToast?.message, "Auto")

        // Auto's 50ms timer fires, dismisses, and dequeues Next.
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(state.currentToast?.message, "Next")
    }

    func testQueueCapsAtThreePending() async throws {
        state.showToast("Visible", style: .info, duration: 5)
        for message in ["A", "B", "C", "D"] {
            state.showToast(message, style: .info, duration: 5)
        }
        XCTAssertEqual(state.currentToast?.message, "Visible")

        state.dismissCurrentToast()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(state.currentToast?.message, "B", "Oldest pending (A) should have been dropped")

        // Drain: B, C, D remain in order.
        for expected in ["C", "D"] {
            state.dismissCurrentToast()
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(state.currentToast?.message, expected)
        }

        state.dismissCurrentToast()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNil(state.currentToast)
    }
}
