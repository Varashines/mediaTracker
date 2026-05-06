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
        
        // Run the stale metadata healer in the background
        Task.detached(priority: .background) {
            let context = ModelContext(container)
            let now = Date()
            
            // Look for items currently marked as upcoming or with a badge that might be stale
            let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.storedIsUpcoming == true && $0.cachedNextAiringDate != nil && $0.cachedNextAiringDate! < now })
            
            if let staleItems = try? context.fetch(descriptor), !staleItems.isEmpty {
                print("♻️ Background Task: Auto-healing \(staleItems.count) stale items...")
                for item in staleItems {
                    item.syncCachedProperties()
                }
                try? context.save()
            }
            
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
}
