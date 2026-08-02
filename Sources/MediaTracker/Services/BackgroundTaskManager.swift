import Foundation
import SwiftData
import SQLite3

#if os(macOS)
import AppKit
#endif

import Observation

/// Coordinates background synchronization and database healing tasks while the app is idle or closed.
@MainActor
@Observable
class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    var isImportActive: Bool = false
    var activeTaskDescription: String? = nil

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
        guard let container = container, !isImportActive else { isDripSyncing = false; return }
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
                
                // Rebuild hub counts after drip sync populates cachedWatchProviders
                let sync = DiscoverySyncService(modelContainer: container)
                try? await BackgroundOperationGate.shared.performSync(container: container) {
                    await sync.syncLibrary(force: true)
                }
                
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
                await self.runPosterColorMigrationV6IfNeeded()
                await self.runPosterColorMigrationV7IfNeeded()
                await self.runWatchProviderMigrationIfNeeded()
                await self.runNetworkKindMigrationIfNeeded()
                await self.migrateWatchDatesFromLegacyStoreIfNeeded()
            }
        }

        // Schedule automated JSON backup (daily)
        Task.detached(priority: .background) {
            await self.runAutomatedBackup()
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

                let syncItems: [(id: String, network: String?, genres: [String], language: String?, badge: String?, providers: [String])] = stale.map {
                    ($0.id, $0.cachedNetwork, $0.cachedGenres, $0.cachedLanguage, $0.storedSmartBadgeLabel, $0.cachedWatchProviders)
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
                    await sync.updateItemDeleted(network: entry.network, genres: entry.genres, language: entry.language, badge: entry.badge, providers: entry.providers)
                }

                await MainActor.run {
                    MediaStateService.shared.postMediaStateChanged()
                }
            }
        } catch {
            AppLogger.error("🗑️ Soft-delete purge failed: \(error.localizedDescription)", logger: AppLogger.background)
        }
    }

    /// One-shot migration: re-extract dominant poster colors using the median-cut + Vision saliency algorithm (v6).
    /// Runs in the background, chunked, gated by `BackgroundOperationGate` to avoid overlap with
    /// other heavy work. Safe to call repeatedly — it bails immediately if the version flag is already set.
    func runPosterColorMigrationV6IfNeeded() async {
        let currentVersion = UserDefaults.standard.integer(forKey: "colorExtractionVersion")
        guard currentVersion < 6 else { return }
        guard let container = container else { return }

        let extractionVersionKey = "colorExtractionVersion"
        let batchSize = 50
        let interBatchSleepNs: UInt64 = 250_000_000

        do {
            try await BackgroundOperationGate.shared.performExtract(label: "posterColorMigrationV6", container: container) {
                let context = ModelContext(container)

                var descriptor = FetchDescriptor<MediaItem>(
                    sortBy: [SortDescriptor(\.lastInteractionDate, order: .reverse)]
                )
                descriptor.propertiesToFetch = [\.id, \.posterURL, \.themeColorHex, \.themeColorSourceURL, \.lastInteractionDate]
                let allItems = (try? context.fetch(descriptor)) ?? []

                var processed = 0
                let total = allItems.count
                AppLogger.info("🎨 Poster color migration v6 starting: \(total) items", logger: AppLogger.background)

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
                        item.themeColorHex = pair.primary.toHex()
                        item.themeColorSourceURL = poster
                    }

                    processed += 1
                    if processed % batchSize == 0 {
                        try? context.save()
                        // Save progress incrementally so interrupted migrations don't restart
                        UserDefaults.standard.set(6, forKey: extractionVersionKey)
                        try? await Task.sleep(nanoseconds: interBatchSleepNs)
                    }
                }

                try? context.save()
                UserDefaults.standard.set(6, forKey: extractionVersionKey)
                AppLogger.info("🎨 Poster color migration v6 complete: \(processed) items", logger: AppLogger.background)
            }
        } catch {
            AppLogger.error("🎨 Poster color migration v6 failed: \(error.localizedDescription)", logger: AppLogger.background)
        }
    }

    /// v7: re-extracts the premium poster palette (primary/secondary/muted) for every item.
    func runPosterColorMigrationV7IfNeeded() async {
        let currentVersion = UserDefaults.standard.integer(forKey: "colorExtractionVersion")
        guard currentVersion < 7 else { return }
        guard let container = container else { return }

        let extractionVersionKey = "colorExtractionVersion"
        let batchSize = 50
        let interBatchSleepNs: UInt64 = 250_000_000

        do {
            try await BackgroundOperationGate.shared.performExtract(label: "posterColorMigrationV7", container: container) {
                let context = ModelContext(container)

                var descriptor = FetchDescriptor<MediaItem>(
                    sortBy: [SortDescriptor(\.lastInteractionDate, order: .reverse)]
                )
                descriptor.propertiesToFetch = [
                    \.id, \.posterURL, \.themeColorHex, \.themeColorSourceURL,
                    \.themeSecondaryColorHex, \.themeMutedColorHex, \.lastInteractionDate
                ]
                let allItems = (try? context.fetch(descriptor)) ?? []

                var processed = 0
                let total = allItems.count
                AppLogger.info("🎨 Poster color migration v7 starting: \(total) items", logger: AppLogger.background)

                for item in allItems {
                    try Task.checkCancellation()
                    guard !item.isDeleted else { continue }
                    guard let poster = item.posterURL, let url = URL(string: poster) else { continue }

                    var cgImage: CGImage?
                    if let cached = await ImageCache.shared.get(forKey: poster, targetSize: CGSize(width: 200, height: 300)) {
                        cgImage = cached.image
                    } else if let (data, _) = try? await ImageCache.shared.imageSession.data(from: url),
                              let image = NSImage(data: data) {
                        cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    }

                    if let cgImage {
                        let palette = await ColorExtractor.extractThemePalette(from: cgImage)
                        item.themeColorHex = palette.primary.toHex()
                        item.themeSecondaryColorHex = palette.secondary.toHex()
                        item.themeMutedColorHex = palette.muted.toHex()
                        item.themeColorSourceURL = poster
                    }

                    processed += 1
                    if processed % batchSize == 0 {
                        try? context.save()
                        UserDefaults.standard.set(7, forKey: extractionVersionKey)
                        try? await Task.sleep(nanoseconds: interBatchSleepNs)
                    }
                }

                try? context.save()
                UserDefaults.standard.set(7, forKey: extractionVersionKey)
                AppLogger.info("🎨 Poster color migration v7 complete: \(processed) items", logger: AppLogger.background)
            }
        } catch {
            AppLogger.error("🎨 Poster color migration v7 failed: \(error.localizedDescription)", logger: AppLogger.background)
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
            await runPosterColorMigrationV6IfNeeded()
        }

        // Secondary Background Tasks
        Task.detached(priority: .background) {
            let context = ModelContext(container)

            // Automated Rolling Backup
            // Map MediaItem (non-Sendable) → LibraryBackup (Sendable) on the background context
            // BEFORE crossing into the @MainActor LibraryImportExportService boundary.
            var backupDesc = FetchDescriptor<MediaItem>()
            backupDesc.propertiesToFetch = [
                \.id, \.title, \.typeValue, \.stateValue, \.dateAdded, \.tasteValue, \.lastInteractionDate,
                \.posterURL, \.overview, \.backdropURL, \.releaseDate, \.lastUpdated, \.titleLogoURL,
                \.themeColorHex, \.cachedRuntime, \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount,
                \.remainingEpisodesCount, \.cachedLanguage, \.cachedNetwork, \.cachedNetworkLogoPath, \.mood
            ]
            if let allItems = try? context.fetch(backupDesc) {
                let exportItems = allItems.map { item -> MediaItemData in
                    var watchedIDs: [String]? = nil
                    var watchedDates: [String: Date]? = nil
                    if item.type == .tvShow, let tv = item.tvShowDetails {
                        let watchedEps = tv.seasons
                            .liveModels
                            .flatMap { $0.episodes.liveModels }
                            .filter { $0.isWatched }
                        watchedIDs = watchedEps.map { $0.uniqueID ?? "" }
                        watchedDates = Dictionary(uniqueKeysWithValues: watchedEps.compactMap { ep in
                            ep.uniqueID.flatMap { ($0, ep.lastWatchedDate ?? Date()) }
                        })
                    }
                    return MediaItemData(item: item, watchedIDs: watchedIDs, watchedDates: watchedDates)
                }

                var collectionBackup: [CollectionBackupData]? = nil
                let collectionsDescriptor = FetchDescriptor<MediaCollection>()
                if let allCollections = try? context.fetch(collectionsDescriptor) {
                    collectionBackup = allCollections.map { col in
                        let itemIDs: [String]? = col.isSmart ? nil : col.items.compactMap { $0.modelContext != nil ? $0.id : nil }
                        return CollectionBackupData(
                            id: col.id,
                            name: col.name,
                            systemImage: col.systemImage,
                            notes: col.notes,
                            isPinned: col.isPinned,
                            completedItemIDs: col.completedItemIDs,
                            smartRulesData: col.smartRulesData,
                            itemIDs: itemIDs
                        )
                    }
                }

                let backup = LibraryBackup(items: exportItems, collections: collectionBackup)
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
                    item.syncCachedProperties(now: now, dirty: [.badge])
                }
                await BadgeEngine.flushBadgeChanges(container: container)
                try context.save()
                
                // syncLibrary is no longer needed here — badge deltas were flushed above
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

    /// One-shot migration: loads watch providers from local cache files on disk into the new SwiftData attributes
    /// on MediaItem. This enables the Discovery Hub Streaming Providers section to work instantly without requiring
    /// manual forced refreshes of the whole library.
    func runWatchProviderMigrationIfNeeded() async {
        let migrationVersionKey = "watchProviderMigrationVersion"
        let currentVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        guard currentVersion < 3 else { return }
        guard let container = container else { return }

        // --- v2 migration (legacy) ---
        if currentVersion < 2 {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.propertiesToFetch = [\.id, \.typeValue, \.cachedWatchProviders]
            
            let allItems = (try? context.fetch(descriptor)) ?? []
            
            if allItems.isEmpty {
                UserDefaults.standard.set(2, forKey: migrationVersionKey)
            } else {
                AppLogger.info("📦 Watch Provider migration v2 starting for \(allItems.count) items...", logger: AppLogger.background)
                
                var migratedCount = 0
                for item in allItems {
                    guard !Task.isCancelled else { return }
                    
                    if !item.cachedWatchProviders.isEmpty {
                        continue
                    }
                    
                    guard let tmdbIDString = item.id.split(separator: "_").last,
                          let tmdbID = Int(tmdbIDString) else { continue }
                    
                    let type = item.type ?? .movie
                    
                    let providers = await APIClient.shared.fetchWatchProviders(tmdbID: tmdbID, type: type)
                    if !providers.isEmpty {
                        item.cachedWatchProviders = providers.map { $0.name }
                        migratedCount += 1
                    }
                }
                
                if migratedCount > 0 {
                    try? context.save()
                    AppLogger.info("📦 Watch Provider migration v2 completed: migrated \(migratedCount) items", logger: AppLogger.background)
                    let sync = DiscoverySyncService(modelContainer: container)
                    await sync.syncLibrary(force: true)
                    await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
                }
                UserDefaults.standard.set(2, forKey: migrationVersionKey)
            }
        }

        // --- v3 migration: backfill items still missing providers (batched) ---
        do {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.propertiesToFetch = [\.id, \.typeValue, \.cachedWatchProviders]
            descriptor.fetchLimit = 500
            
            var allNeedsBackfill: [MediaItem] = []
            var offset = 0
            var hasMore = true
            
            while hasMore {
                descriptor.fetchOffset = offset
                let batch = (try? context.fetch(descriptor)) ?? []
                hasMore = batch.count == 500
                allNeedsBackfill.append(contentsOf: batch.filter { $0.cachedWatchProviders.isEmpty })
                offset += 500
            }
            
            guard !allNeedsBackfill.isEmpty else {
                AppLogger.info("📦 Watch Provider migration v3: all items already have providers", logger: AppLogger.background)
                UserDefaults.standard.set(3, forKey: migrationVersionKey)
                return
            }
            
            AppLogger.info("📦 Watch Provider migration v3 starting: \(allNeedsBackfill.count) items need backfill...", logger: AppLogger.background)
            
            let batchSize = 50
            var migratedCount = 0
            var processed = 0
            
            for item in allNeedsBackfill {
                guard !Task.isCancelled else { return }
                
                guard let tmdbIDString = item.id.split(separator: "_").last,
                      let tmdbID = Int(tmdbIDString) else { continue }
                
                let type = item.type ?? .movie
                
                let providers = await APIClient.shared.fetchWatchProviders(tmdbID: tmdbID, type: type)
                if !providers.isEmpty {
                    item.cachedWatchProviders = providers.map { $0.name }
                    migratedCount += 1
                }
                
                processed += 1
                if processed % batchSize == 0 {
                    try? context.save()
                    AppLogger.info("📦 Watch Provider migration v3 progress: \(processed)/\(allNeedsBackfill.count) (\(migratedCount) migrated)", logger: AppLogger.background)
                }
            }
            
            try? context.save()
            AppLogger.info("📦 Watch Provider migration v3 completed: \(migratedCount)/\(allNeedsBackfill.count) items migrated", logger: AppLogger.background)
            
            if migratedCount > 0 {
                let sync = DiscoverySyncService(modelContainer: container)
                await sync.syncLibrary(force: true)
                await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
            }
            
            UserDefaults.standard.set(3, forKey: migrationVersionKey)
        }
    }

    /// One-shot migration: backfill NetworkEntity.kind based on item types
    func runNetworkKindMigrationIfNeeded() async {
        let migrationVersionKey = "networkKindMigrationVersion"
        let currentVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        guard currentVersion < 1 else { return }
        guard let container = container else { return }

        let context = ModelContext(container)

        // 1. Count networks by kind from items (batched)
        var networkKindCounts: [String: (network: Int, studio: Int)] = [:]
        var itemDesc = FetchDescriptor<MediaItem>()
        itemDesc.propertiesToFetch = [\.cachedNetwork, \.typeValue]
        itemDesc.fetchLimit = 500
        var itemOffset = 0
        var hasMoreItems = true
        
        while hasMoreItems {
            itemDesc.fetchOffset = itemOffset
            let batch = (try? context.fetch(itemDesc)) ?? []
            hasMoreItems = batch.count == 500
            
            for item in batch {
                guard let rawName = item.cachedNetwork else { continue }
                let names = rawName.commaSeparatedValues
                let isMovie = item.typeValue == "Movie"
                for name in names where !name.isEmpty {
                    var counts = networkKindCounts[name] ?? (network: 0, studio: 0)
                    if isMovie { counts.studio += 1 } else { counts.network += 1 }
                    networkKindCounts[name] = counts
                }
            }
            itemOffset += 500
        }

        // 2. Update NetworkEntity.kind
        var entityDesc = FetchDescriptor<NetworkEntity>()
        entityDesc.propertiesToFetch = [\.name, \.kind]
        let entities = (try? context.fetch(entityDesc)) ?? []
        var updated = 0
        for entity in entities {
            if let counts = networkKindCounts[entity.name] {
                let newKind = counts.studio > counts.network ? "studio" : "network"
                if entity.kind != newKind {
                    entity.kind = newKind
                    updated += 1
                }
            }
        }

        if updated > 0 {
            try? context.save()
            AppLogger.info("🏷️ Network kind migration: updated \(updated) entities", logger: AppLogger.background)
            let sync = DiscoverySyncService(modelContainer: container)
            await sync.syncLibrary(force: true)
            await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
        }

        UserDefaults.standard.set(1, forKey: migrationVersionKey)
    }

    // MARK: - Watch-Dates Recovery Migration

    /// One-shot migration: pulls the real `lastInteractionDate` / episode
    /// `lastWatchedDate` values out of the legacy store (saved aside before the
    /// rewatch-schema cleanup) and patches the current store, so "Recently
    /// Watched" reflects true watch times after a restore.
    func migrateWatchDatesFromLegacyStoreIfNeeded() async {
        let flag = "watchDatesMigrationV1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        guard let container else { return }

        let legacyPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/default_store_backup_rewatch/default.store")

        guard FileManager.default.fileExists(atPath: legacyPath.path) else {
            UserDefaults.standard.set(true, forKey: flag)
            return
        }

        // Read the legacy store off the main actor (read-only).
        let path = legacyPath.path
        let (itemDates, episodeDates) = await Task.detached(priority: .utility) {
            (Self.readLastInteractionDates(from: path), Self.readEpisodeWatchDates(from: path))
        }.value

        guard !itemDates.isEmpty || !episodeDates.isEmpty else {
            UserDefaults.standard.set(true, forKey: flag)
            return
        }

        let context = ModelContext(container)
        if !itemDates.isEmpty {
            var itemDesc = FetchDescriptor<MediaItem>()
            itemDesc.propertiesToFetch = [\.id]
            let items = (try? context.fetch(itemDesc)) ?? []
            var updated = 0
            for item in items {
                // Overwrite the flattened import-time date with the real legacy date.
                if let date = itemDates[item.id] {
                    item.lastInteractionDate = date
                    updated += 1
                }
            }
            if updated > 0 { AppLogger.info("📅 Watch-dates migration: restored \(updated) items", logger: AppLogger.background) }
        }

        if !episodeDates.isEmpty {
            var epDesc = FetchDescriptor<TVEpisode>()
            epDesc.propertiesToFetch = [\.uniqueID, \.isWatched, \.lastWatchedDate]
            let episodes = (try? context.fetch(epDesc)) ?? []
            var updated = 0
            for ep in episodes where ep.isWatched {
                if let uid = ep.uniqueID, let date = episodeDates[uid] {
                    ep.lastWatchedDate = date
                    updated += 1
                }
            }
            if updated > 0 { AppLogger.info("📅 Watch-dates migration: restored \(updated) episodes", logger: AppLogger.background) }
        }

        try? context.save()
        await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
        UserDefaults.standard.set(true, forKey: flag)
    }

    private nonisolated static func readLastInteractionDates(from path: String) -> [String: Date] {
        readDates(path: path, query: "SELECT ZID, ZLASTINTERACTIONDATE FROM ZMEDIAITEM WHERE ZLASTINTERACTIONDATE IS NOT NULL")
    }

    private nonisolated static func readEpisodeWatchDates(from path: String) -> [String: Date] {
        readDates(path: path, query: "SELECT ZUNIQUEID, ZLASTWATCHEDDATE FROM ZTVEPISODE WHERE ZLASTWATCHEDDATE IS NOT NULL")
    }

    private nonisolated static func readDates(path: String, query: String) -> [String: Date] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var result: [String: Date] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idC = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: idC)
            let ts = sqlite3_column_double(stmt, 1)
            if ts > 0 {
                result[id] = Date(timeIntervalSinceReferenceDate: ts)
            }
        }
        return result
    }

    // MARK: - Automated JSON Backup
    private var lastBackupKey: String { "com.vara.mediatracker.lastAutoBackup" }

    private func runAutomatedBackup() async {
        let lastBackup = UserDefaults.standard.object(forKey: lastBackupKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastBackup) >= .days7 else { return }

        guard let container else { return }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = [
            \.id, \.title, \.typeValue, \.stateValue, \.dateAdded, \.tasteValue, \.lastInteractionDate,
            \.posterURL, \.overview, \.backdropURL, \.releaseDate, \.lastUpdated, \.titleLogoURL,
            \.themeColorHex, \.cachedRuntime, \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount,
            \.remainingEpisodesCount, \.cachedLanguage, \.cachedNetwork, \.cachedNetworkLogoPath, \.mood
        ]
        let items = (try? context.fetch(descriptor)) ?? []
        guard !items.isEmpty else { return }

        let exportItems = items.map { item -> MediaItemData in
            var watchedIDs: [String]? = nil
            var watchedDates: [String: Date]? = nil
            if item.type == .tvShow, let tv = item.tvShowDetails {
                let watchedEps = tv.seasons.liveModels.flatMap { $0.episodes.liveModels }.filter { $0.isWatched }
                watchedIDs = watchedEps.map { $0.uniqueID ?? "" }
                watchedDates = Dictionary(uniqueKeysWithValues: watchedEps.compactMap { ep in
                    ep.uniqueID.flatMap { ($0, ep.lastWatchedDate ?? Date()) }
                })
            }
            return MediaItemData(item: item, watchedIDs: watchedIDs, watchedDates: watchedDates)
        }

        var collectionBackup: [CollectionBackupData]? = nil
        let collectionsDescriptor = FetchDescriptor<MediaCollection>()
        if let collections = try? context.fetch(collectionsDescriptor) {
            collectionBackup = collections.map { col in
                CollectionBackupData(
                    id: col.id, name: col.name, systemImage: col.systemImage,
                    notes: col.notes, isPinned: col.isPinned,
                    completedItemIDs: col.completedItemIDs, smartRulesData: col.smartRulesData,
                    itemIDs: col.isSmart ? nil : col.items.compactMap { $0.modelContext != nil ? $0.id : nil }
                )
            }
        }

        let backup = LibraryBackup(items: exportItems, collections: collectionBackup)
        await LibraryImportExportService.shared.automatedBackup(backup: backup)
        UserDefaults.standard.set(Date(), forKey: lastBackupKey)
    }
}
