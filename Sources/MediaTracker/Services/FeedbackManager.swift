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
    }
    
    func trigger(_ type: FeedbackType) {
        let hapticsEnabled = UserDefaults.standard.object(forKey: UserDefaultsKeys.hapticsEnabled.rawValue) as? Bool ?? true
        let audioEnabled = UserDefaults.standard.object(forKey: UserDefaultsKeys.audioEnabled.rawValue) as? Bool ?? true

        switch type {
        case .click:
            if hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            
        case .success, .addToLibrary:
            if hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            if audioEnabled {
                NSSound(named: "Bottle")?.play()
            }
            
        case .warning, .removeFromLibrary:
            if hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            if audioEnabled {
                NSSound(named: "Basso")?.play()
            }
            
        case .stateChange:
            if hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            if audioEnabled {
                NSSound(named: "Pop")?.play()
            }

        case .markWatched:
            if hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            if audioEnabled {
                NSSound(named: "Bottle")?.play()
            }

        case .unmarkWatched:
            if hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            if audioEnabled {
                NSSound(named: "Tink")?.play()
            }

        case .tasteLove:
            if hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            if audioEnabled {
                NSSound(named: "Hero")?.play()
            }

        case .tasteLike:
            if hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            if audioEnabled {
                NSSound(named: "Pop")?.play()
            }

        case .tasteDislike:
            if hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
            if audioEnabled {
                NSSound(named: "Basso")?.play()
            }
        }
    }
}
