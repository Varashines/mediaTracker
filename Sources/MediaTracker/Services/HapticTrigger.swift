import SwiftUI
import Observation

/// Hybrid haptic bridge: Views trigger declarative `sensoryFeedback` via this
/// observable, while `FeedbackManager` keeps imperative `NSHaptic` + audio for
/// background/non-View call sites. macOS 15 `sensoryFeedback` respects
/// system Reduce Motion; app toggle `hapticsEnabled` still gates it.
@Observable @MainActor
final class HapticTrigger {
    static let shared = HapticTrigger()

    var token: Int = 0
    var feedback: SensoryFeedback = .selection

    func trigger(_ feedback: SensoryFeedback) {
        let enabled = UserDefaults.standard.object(forKey: UserDefaultsKeys.hapticsEnabled.rawValue) as? Bool ?? true
        guard enabled else { return }
        self.feedback = feedback
        token &+= 1
    }
}

// Map FeedbackManager types to sensoryFeedback kinds (lossy but documented)
extension FeedbackManager.FeedbackType {
    var sensory: SensoryFeedback {
        switch self {
        case .click: return .selection
        case .success, .addToLibrary, .markWatched, .moodSelected: return .success
        case .warning, .removeFromLibrary: return .warning
        case .stateChange, .unmarkWatched, .moodCleared: return .selection
        case .tasteLove: return .impact(weight: .heavy)
        case .tasteLike: return .impact(weight: .light)
        case .tasteDislike: return .impact(weight: .medium)
        }
    }
}
