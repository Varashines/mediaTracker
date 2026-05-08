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
    
    private init() {}
    
    func start(container: ModelContainer) {
        self.container = container
        guard !isScheduled else { return }
        isScheduled = true
        
        // Phase 4 Optimization: Proactive Startup Healer
        // Ensures "SOON" transitions to "NEW" immediately when the app opens.
        Task.detached(priority: .background) {
            await self.refreshStaleBadges()
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
        print("🕒 Scheduled background activity: \(activity.identifier)")
        #endif
    }
    
    private func performBackgroundSync() async {
        guard let container = container else { return }
        print("🔄 Background sync started...")
        
        await refreshStaleBadges()
        
        // Secondary Background Tasks
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            
            // Automated Rolling Backup
            if let allItems = try? context.fetch(FetchDescriptor<MediaItem>()) {
                await LibraryImportExportService.shared.automatedBackup(items: allItems)
            }
            
            // Also run a library discovery sync if needed
            let syncService = DiscoverySyncService(modelContainer: container)
            await syncService.syncLibrary(force: false)
            
            // Run Maintenance/Heal
            let maintenance = MaintenanceService(modelContainer: container)
            try? await maintenance.performLibraryHeal()
        }
    }
    
    /// Scans for items that have crossed a time threshold (e.g. from Upcoming to Recent)
    /// and triggers a badge recalculation so the UI is always accurate.
    private func refreshStaleBadges() async {
        guard let container = container else { return }
        let context = ModelContext(container)
        let now = Date()
        
        // 1. Target Items in the "Transition Zone"
        // - storedIsUpcoming is true, but air date is in the past -> should be NEW/RECENT
        // - smart badge is SOON, but air date is in the past -> should be NEW
        let transitionPredicate = #Predicate<MediaItem> { item in
            (item.storedIsUpcoming == true && item.cachedNextAiringDate != nil && item.cachedNextAiringDate! < now) ||
            (item.storedSmartBadgeLabel == "SOON" && item.cachedNextAiringDate != nil && item.cachedNextAiringDate! < now)
        }
        
        let descriptor = FetchDescriptor<MediaItem>(predicate: transitionPredicate)
        
        do {
            let staleItems = try context.fetch(descriptor)
            if !staleItems.isEmpty {
                print("♻️ Startup Healer: Recalculating badges for \(staleItems.count) transition titles...")
                for item in staleItems {
                    item.syncCachedProperties()
                }
                try context.save()
                
                // Broadcast to update UI
                await MainActor.run {
                    NotificationCenter.default.post(name: .mediaStateChanged, object: nil)
                }
            }
        } catch {
            print("❌ Startup Healer error: \(error)")
        }
    }
}
