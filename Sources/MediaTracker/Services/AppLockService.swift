import Foundation
import LocalAuthentication
import Observation

/// Biometric-only app lock (macOS Touch ID). Locking is a UI privacy gate:
/// it never blocks the SwiftData store or the separate Settings scene.
@MainActor
@Observable
final class AppLockService {
    static let shared = AppLockService()

    private(set) var isLocked = false

    /// Whether the app should require unlock on launch / return-from-inactive.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: UserDefaultsKeys.appLockEnabled.rawValue)
            if isEnabled { lock() } else { isLocked = false }
        }
    }

    /// Touch ID (and an enrolled finger/passcode fallback) is available.
    static var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Whether the user can authenticate at all — Touch ID *or* the account password.
    ///
    /// The lock used to be biometric-only, so a user who removed their fingerprints in
    /// System Settings silently lost the lock: `lock()` returned early and the app opened
    /// straight into the library. `.deviceOwnerAuthentication` keeps the lock enforceable
    /// because macOS falls back to the login password.
    static var ownerAuthenticationAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.appLockEnabled.rawValue)
    }

    /// Locks the app. No-ops only if the lock is disabled or no authentication method
    /// exists at all (so the user is never trapped behind an unenforceable lock).
    func lock() {
        guard isEnabled, Self.ownerAuthenticationAvailable else { return }
        isLocked = true
    }

    func unlock() {
        isLocked = false
    }

    /// Prompts for Touch ID, falling back to the account password. Returns true only on
    /// successful authentication.
    func requestBiometricUnlock() async -> Bool {
        guard Self.ownerAuthenticationAvailable else { return false }
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock MediaTracker"
            )
        } catch {
            return false
        }
    }
}
