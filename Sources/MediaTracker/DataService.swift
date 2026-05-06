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
        // Skip if app is in sleep mode
        guard !SleepManager.shared.isAsleep else { return }

        let itemIDs = items.map { $0.id }

        // Phase 4 Optimization: Coalesce into Batch Queue
        pendingRefreshIDs.formUnion(itemIDs)
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
            let service = MaintenanceService(modelContainer: container)
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
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<MediaItem>()
            if let items = try? context.fetch(descriptor) {
                for item in items {
                    item.syncCachedProperties()
                }
                try? context.save()
                
                await MainActor.run {
                    AppErrorState.shared.showToast("All badges updated.", systemImage: "checkmark.circle.fill", type: .success)
                }
            }
        }
    }

    func clearDatabase(modelContext: ModelContext) {
        Task { @MainActor in
            do {
                try modelContext.delete(model: MediaItem.self)
                try modelContext.delete(model: NetworkEntity.self)
                try modelContext.delete(model: GenreEntity.self)
                try modelContext.delete(model: LanguageEntity.self)
                try modelContext.delete(model: MediaCollection.self)
                try modelContext.save()
                
                // Clear caches as well
                ImageCache.shared.clearFullCache()
                URLCache.shared.removeAllCachedResponses()
                
                AppErrorState.shared.showToast("Database cleared successfully.", systemImage: "trash", type: .success)
                NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
            } catch {
                AppErrorState.shared.surfaceError("Failed to clear database: \(error.localizedDescription)")
            }
        }
    }
}
