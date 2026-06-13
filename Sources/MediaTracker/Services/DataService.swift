import Foundation
import SwiftData

@MainActor @Observable
class DataService {
    static let shared = DataService()

    var isRefreshing: Bool = false
    /// Tracks items refreshed during this app session to avoid redundant network calls.
    private var sessionRefreshedItems = Set<String>()

    /// Batch Queue for coalescing metadata refresh requests
    private var pendingRefreshIDs = Set<String>()
    private var refreshTask: Task<Void, Never>?
    /// Tracks items currently being added to prevent race conditions and duplicates.
    private var itemsInProgress = Set<String>()

    // Feedback State
    var isRunningMaintenance = false
    private var modelContainer: ModelContainer?
    nonisolated(unsafe) static var modelContainer: ModelContainer?

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        DataService.modelContainer = container
    }

    func isProcessing(id: String) -> Bool { itemsInProgress.contains(id) }
    func startProcessing(id: String) { itemsInProgress.insert(id) }
    func stopProcessing(id: String) { itemsInProgress.remove(id) }

    func hasRefreshedThisSession(id: String) -> Bool {
        sessionRefreshedItems.contains(id)
    }

    func markAsRefreshedThisSession(id: String) {
        sessionRefreshedItems.insert(id)
    }

    func refreshMetadata(for items: [MediaItem], modelContext: ModelContext, metadataOnly: Bool = false, force: Bool = false, skipDelay: Bool = false) {
        refreshMetadata(forIDs: items.map { $0.id }, modelContext: modelContext, metadataOnly: metadataOnly, force: force, skipDelay: skipDelay)
    }

    func refreshMetadata(forIDs ids: [String], modelContext: ModelContext, metadataOnly: Bool = false, force: Bool = false, skipDelay: Bool = false) {
        guard !SleepManager.shared.isAsleep else { return }

        let unrefreshedIDs = force ? ids : ids.filter { !hasRefreshedThisSession(id: $0) }
        guard !unrefreshedIDs.isEmpty else { return }

        pendingRefreshIDs.formUnion(unrefreshedIDs)
        refreshTask?.cancel()

        isRefreshing = true

        refreshTask = Task {
            if !skipDelay {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            if Task.isCancelled {
                self.isRefreshing = false
                return
            }

            let idsToProcess = Array(pendingRefreshIDs)
            pendingRefreshIDs.removeAll()

            if !idsToProcess.isEmpty {
                let backgroundService = BackgroundDataService(modelContainer: modelContext.container)
                await backgroundService.refreshMetadata(for: idsToProcess, metadataOnly: metadataOnly, force: force)
                idsToProcess.forEach { markAsRefreshedThisSession(id: $0) }
            }

            self.isRefreshing = false
        }
    }
    
    func runMaintenance(modelContext: ModelContext, silent: Bool = false) {
        guard !isRunningMaintenance else { return }
        isRunningMaintenance = true

        let container = modelContext.container
        Task.detached(priority: .background) {
            let service = BackgroundDataService(modelContainer: container)
            do {
                try await BackgroundOperationGate.shared.performHeal(label: "runMaintenance", container: container) {
                    try await service.performLibraryHeal()
                }
                await MainActor.run {
                    self.isRunningMaintenance = false
                    if !silent {
                        AppErrorState.shared.showToast("Library repair complete.", style: .success)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isRunningMaintenance = false
                    if !silent {
                        AppErrorState.shared.surfaceError("Library repair failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func refreshAllBadges(modelContext: ModelContext) {
        AppErrorState.shared.showToast("Recalculating badges...", style: .info)
        runMaintenance(modelContext: modelContext, silent: false)
    }

    func clearDatabase(modelContext: ModelContext) {
        let container = modelContext.container
        Task.detached(priority: .background) {
            let service = BackgroundDataService(modelContainer: container)
            await service.clearDatabase()
            
            await MainActor.run {
                AppErrorState.shared.showToast("Database cleared successfully.", style: .success)
                MediaStateService.shared.postMediaStateChanged()
            }
        }
    }
}
