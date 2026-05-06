import Foundation
import SwiftData

/// A global actor responsible for debouncing database save requests.
/// This prevents thread locking and IO bottlenecks when users rapidly toggle multiple episodes.
@MainActor
class SaveCoordinator {
    static let shared = SaveCoordinator()
    
    private var saveTask: Task<Void, Never>?
    
    /// Requests a save operation, which will be executed after a short delay (debounce).
    /// If another request comes in before the delay finishes, the timer resets.
    func requestSave(_ context: ModelContext, delayMs: UInt64 = 1000) {
        saveTask?.cancel()
        
        saveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                if Task.isCancelled { return }
                
                try context.save()
            } catch {
                if !(error is CancellationError) {
                    print("❌ SaveCoordinator: Failed to save context - \(error)")
                }
            }
        }
    }
    
    /// Immediately forces a save operation, cancelling any pending debounced saves.
    func forceSave(_ context: ModelContext) {
        saveTask?.cancel()
        try? context.save()
    }
}
