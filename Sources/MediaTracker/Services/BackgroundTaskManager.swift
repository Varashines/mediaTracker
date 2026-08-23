import Foundation
import SwiftData
import SQLite3

#if os(macOS)
import AppKit
#endif

import Observation

@ModelActor
private actor DripSyncSelectionActor {
    func staleOrIncompleteItemIDs(before staleThreshold: Date, limit: Int) throws -> [String] {
        // Priority 1: Incomplete items missing lastUpdated (across all states)
        let incompletePredicate = #Predicate<MediaItem> { item in
            !item.isSoftDeleted && item.lastUpdated == nil
        }
        var incompleteDesc = FetchDescriptor<MediaItem>(predicate: incompletePredicate)
        incompleteDesc.propertiesToFetch = [\.id]
        incompleteDesc.fetchLimit = limit
        let incomplete = try modelContext.fetch(incompleteDesc).map(\.id)
        if !incomplete.isEmpty {
            return incomplete
        }

        // Priority 2: Stale active items
        let stalePredicate = #Predicate<MediaItem> { item in
            !item.isSoftDeleted && item.stateValue == "Active" && (item.lastUpdated == nil || item.lastUpdated! < staleThreshold)
        }
        var staleDesc = FetchDescriptor<MediaItem>(predicate: stalePredicate)
        staleDesc.propertiesToFetch = [\.id]
        staleDesc.fetchLimit = limit
        return try modelContext.fetch(staleDesc).map(\.id)
    }
}

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

    private var isThermalThrottled: Bool {
        ProcessInfo.processInfo.thermalState == .serious
            || ProcessInfo.processInfo.thermalState == .critical
            || ProcessInfo.processInfo.isLowPowerModeEnabled
    }
     
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
        guard !isThermalThrottled else { isDripSyncing = false; return }
        guard NetworkMonitor.shared.isConnected else {
            AppLogger.info("💧 Drip Sync skipped — device is offline", logger: AppLogger.background)
            isDripSyncing = false
            return
        }
        defer { isDripSyncing = false }

        let now = Date()
        let staleThreshold = now.addingTimeInterval(-.days30)
        
        do {
            // Keep database selection off the UI actor. The subsequent service owns
            // its own background context for the heavier metadata work.
            let selector = DripSyncSelectionActor(modelContainer: container)
            let itemIDs = try await selector.staleOrIncompleteItemIDs(before: staleThreshold, limit: 5)
            if !itemIDs.isEmpty {
                AppLogger.info("💧 Drip Sync: Refreshing \(itemIDs.count) stale/incomplete items...", logger: AppLogger.background)
                
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
                await DatabaseMigrations.runAllIfNeeded(container: container)
                await self.backfillMissingLibraryMetadata()
                await self.refreshMissingAirDates(cap: 50)
                await self.refreshStalePremiereBadges()
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
        guard !isThermalThrottled else { return }

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

                let staleIDs = stale.map(\.id)
                FacetIndexMaintenance.removeEntries(forItemIDs: staleIDs, in: context)

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
    
    private func performBackgroundSync() async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep else {
            AppLogger.info("🔄 Background sync skipped — app is sleeping", logger: AppLogger.background)
            return
        }
        AppLogger.info("🔄 Background sync started...", logger: AppLogger.background)

        await refreshStaleBadges()
        await purgeSoftDeleted()

        let isOnline = NetworkMonitor.shared.isConnected
        if isOnline {
            // Opportunistic: backfill per-season aggregate cast for shows that
            // predate the feature (bounded to a few seasons per run).
            await refreshMissingSeasonCast()
            await backfillMissingLibraryMetadata()
            await refreshStalePremiereBadges()
            await refreshMissingAirDates(cap: 15)
        } else {
            AppLogger.info("🔄 Background network sync skipped — device is offline", logger: AppLogger.background)
        }

        // Opportunistic: run migrations if needed.
        await DatabaseMigrations.runAllIfNeeded(container: container)

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

            if isOnline {
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
    }

    
    /// Scans for items that have crossed a time threshold (e.g. from Upcoming to Recent)
    /// and triggers a badge recalculation so the UI is always accurate.
    /// Backfills per-season aggregate cast for shows that predate the feature.
    /// Bounded to a few seasons per run to avoid hammering the API.
    func refreshMissingSeasonCast(cap: Int = 15) async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep else { return }
        let context = ModelContext(container)
        guard let seasons = try? context.fetch(FetchDescriptor<TVSeason>()) else { return }

        let candidates = seasons
            .filter { $0.seasonNumber > 0 && $0.episodeCount > 0 && $0.seasonCast.isEmpty }
            .prefix(cap)
        guard !candidates.isEmpty else { return }

        var fetched = 0
        for season in candidates {
            guard let showID = season.showID else { continue }
            let service = BackgroundDataService(modelContainer: container)
            await service.refreshSeasonCast(tmdbID: showID, seasonNumber: season.seasonNumber)
            fetched += 1
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        AppLogger.info("🎬 Refreshed season cast for \(fetched) seasons", logger: AppLogger.background)
    }

    /// Comprehensive post-import and background backfill:
    /// Refreshes all items missing genres, cast, or child details (TMDB/TVMaze) in concurrent batches.
    func backfillMissingLibraryMetadata(
        priorityIDs: [String] = [],
        onProgress: (@Sendable (Int, Int, String) -> Void)? = nil
    ) async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep || SleepManager.shared.isSleepBlocked else { return }
        guard !isThermalThrottled else { return }

        let context = ModelContext(container)
        var targetIDs = Set(priorityIDs)
        var titleMap: [String: String] = [:]

        // Find all items in the library that are missing metadata
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { !$0.isSoftDeleted })
        descriptor.propertiesToFetch = [\.id, \.title, \.typeValue, \.cachedGenres, \.lastUpdated]
        descriptor.fetchLimit = 500
        var offset = 0
        var hasMore = true

        while hasMore {
            descriptor.fetchOffset = offset
            let batch = (try? context.fetch(descriptor)) ?? []
            hasMore = batch.count == 500

            for item in batch {
                titleMap[item.id] = item.title
                let isMissing = item.lastUpdated == nil
                    || item.cachedGenres.isEmpty
                    || item.storedCast.isEmpty
                    || (item.typeValue == "TV Show" && (item.tvShowDetails == nil || (item.tvShowDetails?.seasons.isEmpty ?? true)))
                    || (item.typeValue == "Movie" && item.movieDetails == nil)
                if isMissing {
                    targetIDs.insert(item.id)
                }
            }
            offset += 500
        }

        guard !targetIDs.isEmpty else {
            AppLogger.info("✅ Backfill check: All library items have complete metadata.", logger: AppLogger.background)
            onProgress?(0, 0, "")
            return
        }

        let allIDs = Array(targetIDs)
        AppLogger.info("🎬 Backfilling metadata for \(allIDs.count) items...", logger: AppLogger.background)

        let backgroundService = BackgroundDataService(modelContainer: container)
        let batchSize = 20
        var processed = 0

        while processed < allIDs.count {
            if isThermalThrottled || (SleepManager.shared.isAsleep && !SleepManager.shared.isSleepBlocked) {
                AppLogger.warning("🌡️ Thermal throttle or sleep during library backfill. Pausing after \(processed)/\(allIDs.count) items.", logger: AppLogger.background)
                break
            }

            let chunk = Array(allIDs[processed..<min(processed + batchSize, allIDs.count)])
            let currentTitle = titleMap[chunk.first ?? ""] ?? ""
            onProgress?(processed, allIDs.count, currentTitle)

            await backgroundService.refreshMetadata(for: chunk, metadataOnly: false, force: false)
            processed += chunk.count
            onProgress?(processed, allIDs.count, currentTitle)

            // Update UI progressively
            await MainActor.run {
                MediaStateService.shared.postMediaStateChanged()
            }

            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // Rebuild hub counts after backfill
        let sync = DiscoverySyncService(modelContainer: container)
        try? await BackgroundOperationGate.shared.performSync(container: container) {
            await sync.syncLibrary(force: true)
        }

        await MainActor.run {
            MediaStateService.shared.postMediaStateChanged()
        }
        AppLogger.info("✅ Backfill complete for \(processed)/\(allIDs.count) items.", logger: AppLogger.background)
        onProgress?(allIDs.count, allIDs.count, "")
    }


    /// Eager local-only heal for PREMIERE — Wishlist/Active/Upcoming whose S01E01 airDate has entered [-inf…+3d] should flip without opening Detail.
    func refreshStalePremiereBadges() async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep else { return }
        guard !isThermalThrottled else { return }
        let context = ModelContext(container)
        let now = Date()
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { ($0.stateValue == "Wishlist" || $0.stateValue == "Active") && $0.isSoftDeleted == false })
        descriptor.propertiesToFetch = [\.id, \.stateValue, \.storedIsUpcoming, \.storedSmartBadgeLabel, \.cachedNextAiringDate, \.releaseDate]
        let candidates = (try? context.fetch(descriptor)) ?? []
        var toRecalc: [MediaItem] = []
        for item in candidates {
            if item.storedSmartBadgeLabel == "PREMIERE" { continue }
            // Use cachedNextAiringDate (first unwatched airDate or tv.nextEpisodeDate) if present, else fallback to releaseDate
            // For Upcoming, cachedNextAiringDate is the premiere date itself
            let nextAir = item.cachedNextAiringDate ?? item.releaseDate
            guard let air = nextAir else { continue }
            let daysSinceAir = now.timeIntervalSince(air) / 86400
            // premiereDaysWindow = -inf ... 3  (any future until 3 days post-air)
            if daysSinceAir <= 3 {
                BadgeEngine.invalidateScan(for: item.persistentModelID)
                toRecalc.append(item)
            }
        }
        guard !toRecalc.isEmpty else { return }
        AppLogger.info("🎬 Premiere heal: recalculating \(toRecalc.count) → PREMIERE candidates", logger: AppLogger.background)
        for item in toRecalc {
            item.syncCachedProperties(dirty: [.badge])
        }
        await BadgeEngine.flushBadgeChanges(container: container)
        try? context.save()
        await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
    }

    /// Backfill missing airDateValue for tracked episodes (where ZAIRDATEVALUE IS NULL) — ensures PREMIERE window has data.
    func refreshMissingAirDates(cap: Int = 25) async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep else { return }
        let context = ModelContext(container)
        // Find TV shows with seasons/episodes missing airDateValue
        var descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.typeValue == "TV Show" && $0.isSoftDeleted == false })
        descriptor.fetchLimit = cap * 2
        let allTV = (try? context.fetch(descriptor)) ?? []
        var candidates: [MediaItem] = []
        for item in allTV {
            guard let tv = item.tvShowDetails else { continue }
            let seasons = tv.seasons.liveModels
            let hasMissingAirDate = seasons.flatMap { $0.episodes.liveModels }.contains { $0.airDateValue == nil }
            if hasMissingAirDate {
                candidates.append(item)
                if candidates.count >= cap { break }
            }
        }
        guard !candidates.isEmpty else { return }
        AppLogger.info("📅 Air-date heal: \(candidates.count) shows with missing episode air dates", logger: AppLogger.background)
        for item in candidates {
            guard let tmdbIDString = item.id.split(separator: "_").last, let tmdbID = Int(tmdbIDString) else { continue }
            let service = BackgroundDataService(modelContainer: container)
            _ = await service.refreshTVShow(id: item.id, tmdbID: tmdbID, metadataOnly: false, force: false)
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
    }

    func refreshStaleBadges() async {
        guard let container = container else { return }
        guard !SleepManager.shared.isAsleep else { return }
        guard !isThermalThrottled else { return }
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

        // Target 4: badges whose meaning can lapse without a model mutation.
        // Recalculate these periodically so their time windows remain accurate.
        let finaleBadge = #Predicate<MediaItem> { $0.storedSmartBadgeLabel == "FINALE" }
        let bingeDropBadge = #Predicate<MediaItem> { $0.storedSmartBadgeLabel == "BINGE DROP" }
        let hookedBadge = #Predicate<MediaItem> { $0.storedSmartBadgeLabel == "HOOKED" }
        let behindBadge = #Predicate<MediaItem> { $0.storedSmartBadgeLabel == "BEHIND" }
        
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
            var finaleDescriptor = FetchDescriptor<MediaItem>(predicate: finaleBadge)
            finaleDescriptor.propertiesToFetch = [\.id, \.storedSmartBadgeLabel, \.cachedNextAiringDate, \.releaseDate]
            let staleFinales = try context.fetch(finaleDescriptor)
            var bingeDropDescriptor = FetchDescriptor<MediaItem>(predicate: bingeDropBadge)
            bingeDropDescriptor.propertiesToFetch = [\.id, \.storedSmartBadgeLabel, \.cachedNextAiringDate, \.releaseDate]
            let staleBingeDrops = try context.fetch(bingeDropDescriptor)
            var hookedDescriptor = FetchDescriptor<MediaItem>(predicate: hookedBadge)
            hookedDescriptor.propertiesToFetch = [\.id, \.storedSmartBadgeLabel, \.cachedNextAiringDate, \.releaseDate]
            let staleHooked = try context.fetch(hookedDescriptor)
            var behindDescriptor = FetchDescriptor<MediaItem>(predicate: behindBadge)
            behindDescriptor.propertiesToFetch = [\.id, \.storedSmartBadgeLabel, \.cachedNextAiringDate, \.releaseDate]
            let staleBehind = try context.fetch(behindDescriptor)

            let allStale = Dictionary(
                (stale1 + stale2 + stale3 + staleFinales + staleBingeDrops + staleHooked + staleBehind)
                    .map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            ).map(\.value)
            
            if !allStale.isEmpty {
                AppLogger.info("♻️ Stale Badge Healer: Recalculating badges for \(allStale.count) transition titles...", logger: AppLogger.background)
                for item in allStale {
                    try Task.checkCancellation()
                    BadgeEngine.invalidateScan(for: item.persistentModelID)
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
