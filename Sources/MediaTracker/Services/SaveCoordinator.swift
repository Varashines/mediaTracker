import Foundation
import SwiftData

/// A global actor responsible for debouncing database save requests.
/// This prevents thread locking and IO bottlenecks when users rapidly toggle multiple episodes.
@MainActor
class SaveCoordinator {
    static let shared = SaveCoordinator()
    
    private struct PendingSave {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var saveTasks: [ObjectIdentifier: PendingSave] = [:]
    
    /// Requests a save operation, which will be executed after a short delay (debounce).
    /// If another request comes in before the delay finishes, the timer resets.
    func requestSave(_ context: ModelContext, delayMs: UInt64 = 350) {
        let id = ObjectIdentifier(context)
        let token = UUID()
        saveTasks[id]?.task.cancel()
        
        let task = Task { @MainActor [weak self, weak context] in
            defer {
                // A cancelled, older task must not clear a newer request for the
                // same context after its sleep resumes.
                if self?.saveTasks[id]?.token == token {
                    self?.saveTasks[id] = nil
                }
            }
            do {
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
                if Task.isCancelled { return }
                // Test contexts (and any closed scene contexts) may have gone
                // away while the debounce timer was pending.
                guard let context else { return }
                try context.save()
            } catch {
                if !(error is CancellationError) {
                    AppErrorState.shared.surfaceError("Failed to save changes: \(error.localizedDescription)")
                }
            }
        }
        saveTasks[id] = PendingSave(token: token, task: task)
    }
    
    /// Immediately forces a save operation, cancelling any pending debounced saves.
    func forceSave(_ context: ModelContext) {
        let id = ObjectIdentifier(context)
        saveTasks[id]?.task.cancel()
        saveTasks[id] = nil
        do {
            try context.save()
        } catch {
            AppErrorState.shared.surfaceError("Failed to save changes: \(error.localizedDescription)")
        }
    }

    /// Cancels all pending debounced saves. Call from XCTest tearDown to avoid
    /// `ModelContext.save() after deallocation` races in full-suite runs.
    func cancelAll() {
        for (_, pendingSave) in saveTasks { pendingSave.task.cancel() }
        saveTasks.removeAll()
    }
}
