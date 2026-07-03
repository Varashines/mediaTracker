import Foundation
import SwiftData

actor BackgroundOperationGate {
    static let shared = BackgroundOperationGate()

    private var isRunning: [String: Bool] = [:]

    func perform(label: String, container: ModelContainer, operation: @Sendable () async throws -> Void) async throws {
        guard !(isRunning[label] ?? false) else {
            AppLogger.debug("⏭️ Skipping \(label) — already running", logger: AppLogger.background)
            return
        }
        isRunning[label] = true
        defer { isRunning[label] = false }
        try await operation()
    }

    func performHeal(label: String = "heal", container: ModelContainer, operation: @Sendable () async throws -> Void) async throws {
        try await perform(label: label, container: container, operation: operation)
    }

    func performSync(label: String = "sync", container: ModelContainer, operation: @Sendable () async throws -> Void) async throws {
        try await perform(label: label, container: container, operation: operation)
    }

    func performExtract(label: String = "extract", container: ModelContainer, operation: @Sendable () async throws -> Void) async throws {
        try await perform(label: label, container: container, operation: operation)
    }

    func performBoth(label: String = "maintenance", container: ModelContainer, heal: @Sendable () async throws -> Void, sync: @Sendable () async throws -> Void) async throws {
        try await perform(label: "\(label)_heal", container: container, operation: heal)
        try await perform(label: "\(label)_sync", container: container, operation: sync)
    }
}
