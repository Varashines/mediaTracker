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

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.appLockEnabled.rawValue)
    }

    /// Locks the app. No-ops if disabled or if biometrics became unavailable
    /// (so the user is never trapped behind an unenforceable lock).
    func lock() {
        guard isEnabled, Self.biometricsAvailable else { return }
        isLocked = true
    }

    func unlock() {
        isLocked = false
    }

    /// Prompts for Touch ID. Returns true only on successful authentication.
    func requestBiometricUnlock() async -> Bool {
        guard Self.biometricsAvailable else { return false }
        let context = LAContext()
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock MediaTracker"
            )
        } catch {
            return false
        }
    }
}
