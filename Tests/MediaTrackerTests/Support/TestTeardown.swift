import XCTest
import ObjectiveC
@testable import MediaTracker

/// Auto-mitigation for SwiftData teardown race: swizzles XCTestCase.tearDown
/// to cancel any pending SaveCoordinator saves before the container deallocates.
private let _mt_swizzle: Void = {
    let original = class_getInstanceMethod(XCTestCase.self, #selector(XCTestCase.tearDown))
    let swizzled = class_getInstanceMethod(XCTestCase.self, #selector(XCTestCase.mt_tearDownSwizzled))
    if let o = original, let s = swizzled {
        method_exchangeImplementations(o, s)
    }
}()

extension XCTestCase {
    @objc func mt_tearDownSwizzled() {
        // Call original tearDown first (now swapped)
        self.mt_tearDownSwizzled()
        // Then cancel pending saves on MainActor
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                SaveCoordinator.shared.cancelAll()
                BadgeEngine.clearScanCache()
            }
        } else {
            DispatchQueue.main.sync {
                SaveCoordinator.shared.cancelAll()
                BadgeEngine.clearScanCache()
            }
        }
    }

    static func _mt_ensureSwizzled() { _ = _mt_swizzle }
}

@MainActor
func mt_cancelPendingSaves() {
    SaveCoordinator.shared.cancelAll()
    BadgeEngine.clearScanCache()
}

// Trigger swizzle at load time
private let _mt_trigger: Void = { XCTestCase._mt_ensureSwizzled() }()
