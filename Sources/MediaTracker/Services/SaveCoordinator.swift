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
        /// Weak, for the same reason the task captures the context weakly: a pending
        /// entry must never be the thing keeping a dead scene's context alive.
        weak var context: ModelContext?
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
                // Deliberately weak: a context captured strongly would outlive its
                // test/scene, and SwiftData contexts do not retain their container —
                // saving then crashes with "ModelContext.save() called after its
                // ModelContainer has been deallocated". Tests cancel pending saves
                // in tearDown (MTTestCase) so nothing fires after teardown.
                guard let context else { return }
                try context.save()
            } catch {
                if !(error is CancellationError) {
                    AppErrorState.shared.surfaceError("Failed to save changes: \(error.localizedDescription)")
                }
            }
        }
        saveTasks[id] = PendingSave(token: token, task: task, context: context)
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

    /// Saves every context that has a debounced save outstanding, right now.
    ///
    /// Called when the app terminates or goes to the background. The debounce window is
    /// 350 ms and main-context autosave is deliberately disabled, so without this a
    /// change made just before ⌘Q never reaches disk — nothing else would flush it.
    func flushAll() {
        let pending = saveTasks
        saveTasks.removeAll()
        for (_, entry) in pending {
            entry.task.cancel()
            // Weak, like the task's own capture: a context whose scene is already gone
            // must be skipped rather than saved after its container died.
            guard let context = entry.context else { continue }
            do {
                try context.save()
            } catch {
                AppLogger.error("Final save failed: \(error.localizedDescription)", logger: AppLogger.data)
            }
        }
    }
}
