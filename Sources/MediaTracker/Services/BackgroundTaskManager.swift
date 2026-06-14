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
                await self.runPosterColorMigrationV4IfNeeded()
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

    /// Hard-deletes items that were soft-deleted more than `retentionSeconds` ago. Safe to call
    /// repeatedly — when nothing matches it returns immediately.
    func purgeSoftDeleted(retentionSeconds: TimeInterval = .secondsInDay) async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep else { return }

        let cutoff = Date().addingTimeInterval(-retentionSeconds)
        do {
            try await BackgroundOperationGate.shared.performExtract(label: "softDeletePurge", container: container) {
                let context = ModelContext(container)
                let predicate = #Predicate<MediaItem> { item in
                    item.isSoftDeleted == true
                }
                var descriptor = FetchDescriptor<MediaItem>(predicate: predicate)
                descriptor.propertiesToFetch = [\.id, \.title, \.softDeletedAt, \.cachedNetwork, \.cachedGenres, \.cachedLanguage, \.storedSmartBadgeLabel]
                let softDeleted = (try? context.fetch(descriptor)) ?? []
                let stale = softDeleted.filter { ($0.softDeletedAt ?? .distantFuture) < cutoff }
                guard !stale.isEmpty else { return }

                AppLogger.info("🗑️ Purging \(stale.count) soft-deleted items past undo window...", logger: AppLogger.background)

                let syncItems: [(id: String, network: String?, genres: [String], language: String?, badge: String?)] = stale.map {
                    ($0.id, $0.cachedNetwork, $0.cachedGenres, $0.cachedLanguage, $0.storedSmartBadgeLabel)
                }

                for item in stale {
                    await NotificationManager.shared.cancelNotification(id: item.id, type: item.type ?? .movie)
                    await ImageCache.shared.removeImage(forKey: item.posterURL)
                    await ImageCache.shared.removeImage(forKey: item.backdropURL)
                    context.delete(item)
                }
                try? context.save()

                for entry in syncItems {
                    let sync = DiscoverySyncService(modelContainer: container)
                    await sync.updateItemDeleted(network: entry.network, genres: entry.genres, language: entry.language, badge: entry.badge)
                }

                await MainActor.run {
                    MediaStateService.shared.postMediaStateChanged()
                }
            }
        } catch {
            AppLogger.error("🗑️ Soft-delete purge failed: \(error.localizedDescription)", logger: AppLogger.background)
        }
    }

    /// One-shot migration: re-extract dominant poster colors using the CoreImage algorithm (v4).
    /// Runs in the background, chunked, gated by `BackgroundOperationGate` to avoid overlap with
    /// other heavy work. Safe to call repeatedly — it bails immediately if the version flag is already set.
    func runPosterColorMigrationV4IfNeeded() async {
        let currentVersion = UserDefaults.standard.integer(forKey: "colorExtractionVersion")
        guard currentVersion < 4 else { return }
        guard let container = container else { return }

        let extractionVersionKey = "colorExtractionVersion"
        let batchSize = 50
        let interBatchSleepNs: UInt64 = 250_000_000

        do {
            try await BackgroundOperationGate.shared.performExtract(label: "posterColorMigrationV4", container: container) {
                let context = ModelContext(container)

                var descriptor = FetchDescriptor<MediaItem>(
                    sortBy: [SortDescriptor(\.lastInteractionDate, order: .reverse)]
                )
                descriptor.propertiesToFetch = [\.id, \.posterURL, \.themeColorHex, \.themeColorSourceURL, \.lastInteractionDate]
                let allItems = (try? context.fetch(descriptor)) ?? []

                var processed = 0
                let total = allItems.count
                AppLogger.info("🎨 Poster color migration v4 starting: \(total) items", logger: AppLogger.background)

                for item in allItems {
                    try Task.checkCancellation()
                    guard !item.isDeleted else { continue }
                    guard let poster = item.posterURL, let url = URL(string: poster) else { continue }

                    // Use image cache first — avoid re-downloading from network
                    var cgImage: CGImage?
                    if let cached = await ImageCache.shared.get(forKey: poster, targetSize: CGSize(width: 200, height: 300)) {
                        cgImage = cached.image
                    } else if let (data, _) = try? await ImageCache.shared.imageSession.data(from: url),
                              let image = NSImage(data: data) {
                        cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    }

                    if let cgImage {
                        let pair = await ColorExtractor.topTwoColors(from: cgImage)
                        let primaryHex = pair.primary.toHex()
                        let secondaryHex = pair.secondary.toHex()
                        item.themeColorHex = "\(primaryHex)|\(secondaryHex)"
                        item.themeColorSourceURL = poster
                    }

                    processed += 1
                    if processed % batchSize == 0 {
                        try? context.save()
                        // Save progress incrementally so interrupted migrations don't restart
                        UserDefaults.standard.set(4, forKey: extractionVersionKey)
                        try? await Task.sleep(nanoseconds: interBatchSleepNs)
                    }
                }

                try? context.save()
                UserDefaults.standard.set(4, forKey: extractionVersionKey)
                AppLogger.info("🎨 Poster color migration v4 complete: \(processed) items", logger: AppLogger.background)
            }
        } catch {
            AppLogger.error("🎨 Poster color migration v4 failed: \(error.localizedDescription)", logger: AppLogger.background)
        }
    }
    
    private func performBackgroundSync() async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep else {
            AppLogger.info("🔄 Background sync skipped — app is sleeping", logger: AppLogger.background)
            return
        }
        AppLogger.info("🔄 Background sync started...", logger: AppLogger.background)

        await refreshStaleBadges()
        await purgeSoftDeleted()

        // Opportunistic: if v4 poster color migration hasn't run yet, kick it off.
        if UserDefaults.standard.integer(forKey: "colorExtractionVersion") < 4 {
            await runPosterColorMigrationV4IfNeeded()
        }

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
        let twoDaysAgo = now.addingTimeInterval(-TimeInterval.days2)
        
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
            var d1 = FetchDescriptor<MediaItem>(predicate: p1)
            d1.propertiesToFetch = [\.id, \.storedSmartBadgeLabel, \.cachedNextAiringDate, \.releaseDate]
            let stale1 = try context.fetch(d1)
            var d2 = FetchDescriptor<MediaItem>(predicate: p2)
            d2.propertiesToFetch = [\.id, \.storedSmartBadgeLabel, \.cachedNextAiringDate]
            let stale2 = try context.fetch(d2)
            var d3 = FetchDescriptor<MediaItem>(predicate: p3)
            d3.propertiesToFetch = [\.id, \.storedSmartBadgeLabel, \.cachedNextAiringDate, \.releaseDate]
            let stale3 = try context.fetch(d3)
            
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
