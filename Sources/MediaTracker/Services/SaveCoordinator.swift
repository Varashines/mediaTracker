import Foundation
import SwiftData

/// A global actor responsible for debouncing database save requests.
/// This prevents thread locking and IO bottlenecks when users rapidly toggle multiple episodes.
@MainActor
class SaveCoordinator {
    static let shared = SaveCoordinator()
    
    private var saveTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    
    /// Requests a save operation, which will be executed after a short delay (debounce).
    /// If another request comes in before the delay finishes, the timer resets.
    func requestSave(_ context: ModelContext, delayMs: UInt64 = 350) {
        let id = ObjectIdentifier(context)
        saveTasks[id]?.cancel()
        
        saveTasks[id] = Task { @MainActor in
            defer { saveTasks[id] = nil }
            do {
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                if Task.isCancelled { return }
                
                try context.save()
            } catch {
                if !(error is CancellationError) {
                    AppErrorState.shared.surfaceError("Failed to save changes: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Immediately forces a save operation, cancelling any pending debounced saves.
    func forceSave(_ context: ModelContext) {
        let id = ObjectIdentifier(context)
        saveTasks[id]?.cancel()
        saveTasks[id] = nil
        try? context.save()
    }
}
