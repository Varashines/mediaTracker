import Foundation
import SwiftData

#if os(macOS)
import AppKit
#endif

/// Coordinates background synchronization and database healing tasks while the app is idle or closed.
@MainActor
class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private var isScheduled = false
    private var container: ModelContainer?
    
    private var isDripSyncing = false
    
    private init() {}
    
    func handleIdleStateChange(isIdle: Bool) {
        if isIdle && !isDripSyncing {
            isDripSyncing = true
            Task {
                await performDripSync()
            }
        } else if !isIdle {
            isDripSyncing = false
        }
    }

    private func performDripSync() async {
        guard let container = container else { isDripSyncing = false; return }
        defer { isDripSyncing = false }

        let context = ModelContext(container)
        let now = Date()
        let staleThreshold = now.addingTimeInterval(-.days30)

        // Prioritize "Active" items that are stale
        let predicate = #Predicate<MediaItem> { item in
            item.stateValue == "Active" && (item.lastUpdated == nil || item.lastUpdated! < staleThreshold)
        }
        
        var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
        descriptor.propertiesToFetch = [\.id]
        descriptor.fetchLimit = 3 // Drip a small amount to keep it silent
        
        do {
            let staleItems = try context.fetch(descriptor)
            if !staleItems.isEmpty {
                AppLogger.info("💧 Drip Sync: Refreshing \(staleItems.count) stale active items...", logger: AppLogger.background)
                let itemIDs = staleItems.map { $0.id }
                
                // Use BackgroundDataService for the heavy lifting
                let backgroundService = BackgroundDataService(modelContainer: container)
                await backgroundService.refreshMetadata(for: itemIDs, metadataOnly: false, force: false)
                
                // broadcast UI update
                await MainActor.run {
                    MediaStateService.shared.postMediaStateChanged()
                }
            }
        } catch {
            AppLogger.error("💧 Drip Sync failed: \(error.localizedDescription)", logger: AppLogger.background)
        }
    }

    func start(container: ModelContainer) {
        self.container = container
        guard !isScheduled else { return }
        isScheduled = true
        
        if !UserDefaults.standard.bool(forKey: UserDefaultsKeys.skipStartupTasks.rawValue) {
            Task.detached(priority: .background) {
                await self.refreshStaleBadges()
            }
        }
        
        #if os(macOS)
        let activity = NSBackgroundActivityScheduler(identifier: "com.mediatracker.backgroundSync")
        // Schedule to run periodically, e.g., every 6 hours
        activity.interval = 6 * 60 * 60
        activity.qualityOfService = .background
        activity.repeats = true
        
        activity.schedule { [weak self] (completion: @escaping NSBackgroundActivityScheduler.CompletionHandler) in
            Task {
                await self?.performBackgroundSync()
                completion(.finished)
            }
        }
        AppLogger.debug("🕒 Scheduled background activity: \(activity.identifier)", logger: AppLogger.background)
        #endif
    }
    
    private func performBackgroundSync() async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep else {
            AppLogger.info("🔄 Background sync skipped — app is sleeping", logger: AppLogger.background)
            return
        }
        AppLogger.info("🔄 Background sync started...", logger: AppLogger.background)

        await refreshStaleBadges()

        // Secondary Background Tasks
        Task.detached(priority: .background) {
            let context = ModelContext(container)

            // Automated Rolling Backup
            // Map MediaItem (non-Sendable) → LibraryBackup (Sendable) on the background context
            // BEFORE crossing into the @MainActor LibraryImportExportService boundary.
            var backupDesc = FetchDescriptor<MediaItem>()
            backupDesc.propertiesToFetch = [
                \.id, \.title, \.typeValue, \.stateValue, \.dateAdded, \.tasteValue
            ]
            if let allItems = try? context.fetch(backupDesc) {
                let exportItems = allItems.map { item -> MediaItemData in
                    var watchedIDs: [String]? = nil
                    if item.type == .tvShow, let tv = item.tvShowDetails {
                        watchedIDs = tv.seasons
                            .liveModels
                            .flatMap { $0.episodes.liveModels }
                            .filter { $0.isWatched }
                            .map { $0.uniqueID ?? "" }
                    }
                    return MediaItemData(
                        id: item.id,
                        title: item.title,
                        type: item.type?.rawValue ?? "Movie",
                        state: item.state?.rawValue ?? "Wishlist",
                        dateAdded: item.dateAdded ?? Date(),
                        taste: item.tasteValue,
                        watchedEpisodeIDs: watchedIDs
                    )
                }
                let backup = LibraryBackup(items: exportItems)
                await LibraryImportExportService.shared.automatedBackup(backup: backup)
            }

            // Serialize sync + heal through the gate to prevent overlapping operations
            try? await BackgroundOperationGate.shared.performBoth(label: "backgroundSync", container: container) {
                let syncService = DiscoverySyncService(modelContainer: container)
                await syncService.syncLibrary(force: false)
            } sync: {
                let maintenance = BackgroundDataService(modelContainer: container)
                try await maintenance.performLibraryHeal()
            }
        }
    }

    
    /// Scans for items that have crossed a time threshold (e.g. from Upcoming to Recent)
    /// and triggers a badge recalculation so the UI is always accurate.
    func refreshStaleBadges() async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep else { return }
        let context = ModelContext(container)
        let now = Date()
        let twoDaysAgo = now.addingTimeInterval(-172800)
        
        let distantFuture = Date.distantFuture
        // Phase 5 Performance: Split complex predicates to avoid compiler timeouts
        // Target 1: Upcoming -> Released (Past air date)
        let p1 = #Predicate<MediaItem> { item in
            item.storedIsUpcoming == true && 
            ((item.cachedNextAiringDate ?? distantFuture < now) ||
             (item.releaseDate ?? distantFuture < now))
        }
        
        // Target 2: SOON -> NEW (Past air date)
        let p2 = #Predicate<MediaItem> { item in
            item.storedSmartBadgeLabel == "SOON" && (item.cachedNextAiringDate ?? distantFuture < now)
        }
        
        // Target 3: NEW -> RECENT (Released > 48h ago)
        let p3 = #Predicate<MediaItem> { item in
            item.storedSmartBadgeLabel == "NEW" && 
            ((item.cachedNextAiringDate ?? distantFuture < twoDaysAgo) ||
             (item.releaseDate ?? distantFuture < twoDaysAgo))
        }
        
        do {
            let stale1 = try context.fetch(FetchDescriptor<MediaItem>(predicate: p1))
            let stale2 = try context.fetch(FetchDescriptor<MediaItem>(predicate: p2))
            let stale3 = try context.fetch(FetchDescriptor<MediaItem>(predicate: p3))
            
            let allStale = stale1 + stale2 + stale3
            
            if !allStale.isEmpty {
                AppLogger.info("♻️ Stale Badge Healer: Recalculating badges for \(allStale.count) transition titles...", logger: AppLogger.background)
                for item in allStale {
                    try Task.checkCancellation()
                    item.syncCachedProperties(now: now)
                }
                try context.save()
                
                // Full recount to fix any drift from concurrent onBadgeChanged tasks
                Task.detached(priority: .background) {
                    try? await BackgroundOperationGate.shared.performSync(label: "refreshStaleBadges", container: container) {
                        let sync = DiscoverySyncService(modelContainer: container)
                        await sync.syncLibrary(force: false)
                    }
                }
                
                // Broadcast to update UI
                await MainActor.run {
                    MediaStateService.shared.postMediaStateChanged()
                }
            }
        } catch {
            AppLogger.error("♻️ Badge update failed: \(error.localizedDescription)", logger: AppLogger.background)
        }
    }
}
