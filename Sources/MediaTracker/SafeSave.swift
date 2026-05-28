import Foundation
import SwiftData

@MainActor
func safeSave(_ context: ModelContext, file: String = #file, line: Int = #line) {
    do {
        try context.save()
    } catch {
        AppErrorState.shared.surfaceError("Save failed: \(error.localizedDescription)")
        AppLogger.error("Save failed at \(file):\(line) — \(error)")
    }
}
