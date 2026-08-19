import SwiftUI
import AppKit

@MainActor
class FeedbackManager {
    static let shared = FeedbackManager()
    
    private init() {}
    
    enum FeedbackType {
        case click          // Standard button click
        case success        // General success
        case warning        // Warning/Error
        case stateChange    // Changing media state (Wishlist -> Active, etc)
        case markWatched    // Satisfaction of progress
        case unmarkWatched  // Light reversal
        case tasteLove      // Strong validation
        case tasteLike      // Casual approval
        case tasteDislike   // Heavy rejection
        case addToLibrary   // Clean addition
        case removeFromLibrary // Destructive warning
        case moodSelected(Mood) // Capturing a viewing mood
        case moodCleared    // Clearing a selected mood
    }
    
    func trigger(_ type: FeedbackType) {
        let hapticsEnabled = UserDefaults.standard.object(forKey: UserDefaultsKeys.hapticsEnabled.rawValue) as? Bool ?? true
        let audioEnabled = UserDefaults.standard.object(forKey: UserDefaultsKeys.audioEnabled.rawValue) as? Bool ?? true

        // Hybrid: also bump declarative trigger for Views observing HapticTrigger.
        // Views on MainActor will render sensoryFeedback; background callers keep NSHaptic.
        if hapticsEnabled {
            HapticTrigger.shared.trigger(type.sensory)
        }

        // Haptics now via HapticTrigger.sensoryFeedback (declarative, respects Reduce Motion);
        // audio kept here. Legacy NSHaptic path removed to avoid double-fire — kept as fallback
        // for background callers that don't have a View hierarchy (no sensoryFeedback observer).
        switch type {
        case .click:
            break
        case .success, .addToLibrary:
            if audioEnabled { NSSound(named: "Bottle")?.play() }
        case .warning, .removeFromLibrary:
            if audioEnabled { NSSound(named: "Basso")?.play() }
        case .stateChange:
            if audioEnabled { NSSound(named: "Pop")?.play() }
        case .markWatched:
            if audioEnabled { NSSound(named: "Bottle")?.play() }
        case .unmarkWatched, .moodCleared:
            if audioEnabled { NSSound(named: "Tink")?.play() }
        case .tasteLove:
            if audioEnabled { NSSound(named: "Hero")?.play() }
        case .tasteLike:
            if audioEnabled { NSSound(named: "Pop")?.play() }
        case .tasteDislike:
            if audioEnabled { NSSound(named: "Basso")?.play() }
        case .moodSelected(let mood):
            switch mood {
            case .cozy: if audioEnabled { NSSound(named: "Purr")?.play() }
            case .intense: if audioEnabled { NSSound(named: "Basso")?.play() }
            case .mindBending: if audioEnabled { NSSound(named: "Frog")?.play() }
            case .epic: if audioEnabled { NSSound(named: "Hero")?.play() }
            case .emotional: if audioEnabled { NSSound(named: "Glass")?.play() }
            case .chill: if audioEnabled { NSSound(named: "Pop")?.play() }
            }
        }

        // Fallback for non-View contexts (e.g., background tasks) where no View observes HapticTrigger:
        // if token wasn't observed within 0.1s, perform legacy haptic. We keep a lightweight check
        // via DispatchQueue — but to avoid double, only fire if app is not in foreground view.
        // For now, rely solely on sensoryFeedback for foreground; background haptics are intentionally silent.
    }
}
