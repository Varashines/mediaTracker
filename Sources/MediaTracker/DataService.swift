import Foundation
import SwiftData
import SwiftUI

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
    var showMaintenanceComplete = false

    private var modelContainer: ModelContainer?
    private var tvShowCompletedObserver: Any?

    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        guard tvShowCompletedObserver == nil else { return }
        
        let container = self.modelContainer
        tvShowCompletedObserver = NotificationCenter.default.addObserver(
            forName: .tvShowMarkedCompleted,
            object: nil,
            queue: nil
        ) { notification in
            guard let itemID = notification.userInfo?["itemID"] as? String,
                  let container = container else { return }
            
            Task.detached(priority: .userInitiated) {
                let backgroundService = BackgroundDataService(modelContainer: container)
                await backgroundService.markAllEpisodesAsWatched(itemID: itemID)
            }
        }
    }

    func isProcessing(id: String) -> Bool { itemsInProgress.contains(id) }
    func startProcessing(id: String) { itemsInProgress.insert(id) }
    func stopProcessing(id: String) { itemsInProgress.remove(id) }

    func hasRefreshedThisSession(id: String) -> Bool {
        return sessionRefreshedItems.contains(id)
    }

    func markAsRefreshedThisSession(id: String) {
        sessionRefreshedItems.insert(id)
    }

    func refreshMetadata(for items: [MediaItem], modelContext: ModelContext, metadataOnly: Bool = false, force: Bool = false, skipDelay: Bool = false) {
        refreshMetadata(forIDs: items.map { $0.id }, modelContext: modelContext, metadataOnly: metadataOnly, force: force, skipDelay: skipDelay)
    }

    func refreshMetadata(forIDs ids: [String], modelContext: ModelContext, metadataOnly: Bool = false, force: Bool = false, skipDelay: Bool = false) {
        // Skip if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        // Phase 4 Optimization: Coalesce into Batch Queue
        pendingRefreshIDs.formUnion(ids)
        refreshTask?.cancel()

        isRefreshing = true

        refreshTask = Task {
            // Wait for potential rapid-fire calls to finish (e.g. during an import or scroll)
            if !skipDelay {
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            }
            if Task.isCancelled { 
                await MainActor.run { self.isRefreshing = false }
                return 
            }

            let idsToProcess = Array(pendingRefreshIDs)
            pendingRefreshIDs.removeAll()

            if !idsToProcess.isEmpty {
                let backgroundService = BackgroundDataService(modelContainer: modelContext.container)
                await backgroundService.refreshMetadata(for: idsToProcess, metadataOnly: metadataOnly, force: force)
            }

            await MainActor.run {
                self.isRefreshing = false
            }
        }
    }
    
    func runMaintenance(modelContext: ModelContext, silent: Bool = false) {
        guard !isRunningMaintenance else { return }
        isRunningMaintenance = true
        
        let container = modelContext.container
        Task.detached(priority: .background) {
            let service = BackgroundDataService(modelContainer: container)
            do {
                try await service.performLibraryHeal()
                await MainActor.run {
                    self.isRunningMaintenance = false
                    self.showMaintenanceComplete = true
                    if !silent {
                        AppErrorState.shared.showToast("Library repair complete.", systemImage: "checkmark.circle.fill", type: .success)
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
        AppErrorState.shared.showToast("Recalculating badges...", systemImage: "sparkles", type: .info)
        
        let container = modelContext.container
        Task.detached(priority: .background) {
            let service = BackgroundDataService(modelContainer: container)
            try? await service.performLibraryHeal()
            
            await MainActor.run {
                AppErrorState.shared.showToast("All badges updated.", systemImage: "checkmark.circle.fill", type: .success)
            }
        }
    }

    func clearDatabase(modelContext: ModelContext) {
        let container = modelContext.container
        Task.detached(priority: .background) {
            let service = BackgroundDataService(modelContainer: container)
            await service.clearDatabase()
            
            await MainActor.run {
                AppErrorState.shared.showToast("Database cleared successfully.", systemImage: "trash", type: .success)
                MediaStateService.shared.postMediaStateChanged()
            }
        }
    }
}
