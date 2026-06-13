import Foundation
import SwiftData

actor BackgroundOperationGate {
    static let shared = BackgroundOperationGate()

    private var isHealing = false
    private var isSyncing = false
    private var isExtracting = false

    func performHeal(label: String = "heal", container: ModelContainer, operation: @Sendable () async throws -> Void) async throws {
        guard !isHealing else {
            AppLogger.debug("⏭️ Skipping heal (\(label)) — another heal is already running", logger: AppLogger.background)
            return
        }
        isHealing = true
        defer { isHealing = false }
        try await operation()
    }

    func performSync(label: String = "sync", container: ModelContainer, operation: @Sendable () async throws -> Void) async throws {
        guard !isSyncing else {
            AppLogger.debug("⏭️ Skipping sync (\(label)) — another sync is already running", logger: AppLogger.background)
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        try await operation()
    }

    func performExtract(label: String = "extract", container: ModelContainer, operation: @Sendable () async throws -> Void) async throws {
        guard !isExtracting else {
            AppLogger.debug("⏭️ Skipping extract (\(label)) — another extract is already running", logger: AppLogger.background)
            return
        }
        isExtracting = true
        defer { isExtracting = false }
        try await operation()
    }

    func performBoth(label: String = "maintenance", container: ModelContainer, heal: @Sendable () async throws -> Void, sync: @Sendable () async throws -> Void) async throws {
        guard !isHealing, !isSyncing else {
            AppLogger.debug("⏭️ Skipping maintenance (\(label)) — heal or sync already running", logger: AppLogger.background)
            return
        }
        isHealing = true
        isSyncing = true
        defer {
            isHealing = false
            isSyncing = false
        }
        try await heal()
        try await sync()
    }
}
