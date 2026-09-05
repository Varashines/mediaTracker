import XCTest
import ObjectiveC
@testable import MediaTracker

/// Auto-mitigation for the SwiftData teardown race: hooks XCTestCase.tearDown
/// to cancel any pending SaveCoordinator saves (and clear the badge scan cache)
/// after each test, before a test's in-memory ModelContainer is deallocated —
/// eliminating the documented full-suite
/// `ModelContext.save() called after its ModelContainer has been deallocated` crash.
///
/// The hook is installed from an INSTANCE property default: XCTest instantiates
/// every test case before running it, so the first instantiation installs it.
/// (Top-level `let` globals are lazily initialized and never referenced
/// anywhere — the original trigger was dead code.)
///
/// Implementation note: this replaces the tearDown IMP directly (chaining the
/// saved original) instead of method_exchangeImplementations with a named
/// replacement selector — framework subclasses (e.g. XCTestSuite) override
/// tearDown and re-dispatch through the base IMP, which broke named-selector
/// swizzling with "unrecognized selector".
class MTTestCase: XCTestCase {
    /// Runs on every instantiation — installs the hook exactly once.
    private let _installTeardownHook: Void = MTTestCase.installHook()

    private static func installHook() -> Void {
        staticsLock.lock()
        defer { staticsLock.unlock() }
        guard !didInstall, let method = class_getInstanceMethod(XCTestCase.self, #selector(XCTestCase.tearDown)) else { return }
        didInstall = true

        let originalIMP = method_getImplementation(method)
        typealias OriginalTearDown = @convention(c) (NSObject, Selector) -> Void
        let originalTearDown = unsafeBitCast(originalIMP, to: OriginalTearDown.self)
        let tearDownSelector = #selector(XCTestCase.tearDown)

        let hook: @convention(block) (NSObject) -> Void = { receiver in
            originalTearDown(receiver, tearDownSelector)
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
        method_setImplementation(method, imp_implementationWithBlock(hook))
    }

    private nonisolated(unsafe) static var didInstall = false
    private static let staticsLock = NSLock()
}
