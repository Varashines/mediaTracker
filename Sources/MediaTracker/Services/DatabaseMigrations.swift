import Foundation
import SwiftData
import SQLite3
#if os(macOS)
import AppKit
#endif

/// Encapsulates one-shot and versioned data migrations away from the runtime scheduler.
enum DatabaseMigrations {

    static func runAllIfNeeded(container: ModelContainer) async {
        await runPosterColorMigrationV6IfNeeded(container: container)
        await runPosterColorMigrationV7IfNeeded(container: container)
        await runWatchProviderMigrationIfNeeded(container: container)
        await runNetworkKindMigrationIfNeeded(container: container)
        await migrateWatchDatesFromLegacyStoreIfNeeded(container: container)
        await reconcileSplitEpisodeWatchDatesIfNeeded(container: container)
    }

    /// One-shot migration: re-extract dominant poster colors using the median-cut + Vision saliency algorithm (v6).
    static func runPosterColorMigrationV6IfNeeded(container: ModelContainer) async {
        let currentVersion = UserDefaults.standard.integer(forKey: "colorExtractionVersion")
        guard currentVersion < 6 else { return }

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
                        try context.save()
                        try await Task.sleep(nanoseconds: interBatchSleepNs)
                    }
                }

                try context.save()
                UserDefaults.standard.set(6, forKey: extractionVersionKey)
                AppLogger.info("🎨 Poster color migration v6 complete: \(processed) items", logger: AppLogger.background)
            }
        } catch {
            AppLogger.error("🎨 Poster color migration v6 failed: \(error.localizedDescription)", logger: AppLogger.background)
        }
    }

    /// v7: re-extracts the premium poster palette (primary/secondary/muted) for every item.
    static func runPosterColorMigrationV7IfNeeded(container: ModelContainer) async {
        let currentVersion = UserDefaults.standard.integer(forKey: "colorExtractionVersion")
        guard currentVersion < 7 else { return }

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
                        try context.save()
                        try await Task.sleep(nanoseconds: interBatchSleepNs)
                    }
                }

                try context.save()
                UserDefaults.standard.set(7, forKey: extractionVersionKey)
                AppLogger.info("🎨 Poster color migration v7 complete: \(processed) items", logger: AppLogger.background)
            }
        } catch {
            AppLogger.error("🎨 Poster color migration v7 failed: \(error.localizedDescription)", logger: AppLogger.background)
        }
    }

    /// One-shot migration: loads watch providers from local cache files into SwiftData attributes.
    static func runWatchProviderMigrationIfNeeded(container: ModelContainer) async {
        let migrationVersionKey = "watchProviderMigrationVersion"
        let currentVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        guard currentVersion < 3 else { return }

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
                    if !item.cachedWatchProviders.isEmpty { continue }
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
                    do {
                        try context.save()
                    } catch {
                        AppLogger.error("📦 Watch Provider migration v2 save failed: \(error.localizedDescription)", logger: AppLogger.background)
                        return
                    }
                    AppLogger.info("📦 Watch Provider migration v2 completed: migrated \(migratedCount) items", logger: AppLogger.background)
                    let sync = DiscoverySyncService(modelContainer: container)
                    await sync.syncLibrary(force: true)
                    await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
                }
                UserDefaults.standard.set(2, forKey: migrationVersionKey)
            }
        }

        // v3 migration: backfill items still missing providers (batched)
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
                    try context.save()
                    AppLogger.info("📦 Watch Provider migration v3 progress: \(processed)/\(allNeedsBackfill.count) (\(migratedCount) migrated)", logger: AppLogger.background)
                }
            }

            try context.save()
            AppLogger.info("📦 Watch Provider migration v3 completed: \(migratedCount)/\(allNeedsBackfill.count) items migrated", logger: AppLogger.background)

            if migratedCount > 0 {
                let sync = DiscoverySyncService(modelContainer: container)
                await sync.syncLibrary(force: true)
                await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
            }

            UserDefaults.standard.set(3, forKey: migrationVersionKey)
        } catch {
            AppLogger.error("📦 Watch Provider migration v3 failed: \(error.localizedDescription)", logger: AppLogger.background)
        }
    }

    /// One-shot migration: backfill NetworkEntity.kind based on item types
    static func runNetworkKindMigrationIfNeeded(container: ModelContainer) async {
        let migrationVersionKey = "networkKindMigrationVersion"
        let currentVersion = UserDefaults.standard.integer(forKey: migrationVersionKey)
        guard currentVersion < 1 else { return }

        let context = ModelContext(container)

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
            do {
                try context.save()
            } catch {
                AppLogger.error("🏷️ Network kind migration save failed: \(error.localizedDescription)", logger: AppLogger.background)
                return
            }
            AppLogger.info("🏷️ Network kind migration: updated \(updated) entities", logger: AppLogger.background)
            let sync = DiscoverySyncService(modelContainer: container)
            await sync.syncLibrary(force: true)
            await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
        }

        UserDefaults.standard.set(1, forKey: migrationVersionKey)
    }

    /// One-shot migration: pulls real watch dates out of legacy store backup
    static func migrateWatchDatesFromLegacyStoreIfNeeded(container: ModelContainer) async {
        let flag = "watchDatesMigrationV1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }

        let legacyPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/default_store_backup_rewatch/default.store")

        guard FileManager.default.fileExists(atPath: legacyPath.path) else {
            UserDefaults.standard.set(true, forKey: flag)
            return
        }

        let path = legacyPath.path
        let (itemDates, episodeDates) = await Task.detached(priority: .utility) {
            (readLastInteractionDates(from: path), readEpisodeWatchDates(from: path))
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
                if let date = itemDates[item.id] {
                    item.lastInteractionDate = date
                    updated += 1
                }
            }
            if updated > 0 { AppLogger.info("📅 Watch-dates migration: restored \(updated) items", logger: AppLogger.background) }
        }

        if !episodeDates.isEmpty {
            var epDesc = FetchDescriptor<TVEpisode>()
            epDesc.propertiesToFetch = [\.uniqueID, \.isWatched, \.lastWatchedDate, \.watchedDate]
            let episodes = (try? context.fetch(epDesc)) ?? []
            var updated = 0
            for ep in episodes where ep.isWatched {
                if let uid = ep.uniqueID, let date = episodeDates[uid] {
                    ep.lastWatchedDate = date
                    ep.watchedDate = date
                    updated += 1
                }
            }
            if updated > 0 { AppLogger.info("📅 Watch-dates migration: restored \(updated) episodes", logger: AppLogger.background) }
        }

        do {
            try context.save()
        } catch {
            AppLogger.error("📅 Watch-dates migration save failed: \(error.localizedDescription)", logger: AppLogger.background)
            return
        }
        await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
        UserDefaults.standard.set(true, forKey: flag)
    }

    private static func readLastInteractionDates(from path: String) -> [String: Date] {
        readDates(path: path, query: "SELECT ZID, ZLASTINTERACTIONDATE FROM ZMEDIAITEM WHERE ZLASTINTERACTIONDATE IS NOT NULL")
    }

    private static func readEpisodeWatchDates(from path: String) -> [String: Date] {
        readDates(path: path, query: "SELECT ZUNIQUEID, ZLASTWATCHEDDATE FROM ZTVEPISODE WHERE ZLASTWATCHEDDATE IS NOT NULL")
    }

    private static func readDates(path: String, query: String) -> [String: Date] {
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

    /// Reconciles newly split 2-part episodes (e.g. from TVMaze/TMDB expansions) so that
    /// recently marked split parts inherit the original watch timestamp of their preceding episode part.
    static func reconcileSplitEpisodeWatchDatesIfNeeded(container: ModelContainer) async {
        let flag = "hasReconciledSplitEpisodeWatchDates_v1"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }

        let context = ModelContext(container)
        var descriptor = FetchDescriptor<TVEpisode>()
        descriptor.propertiesToFetch = [\.showID, \.seasonNumber, \.episodeNumber, \.name, \.isWatched, \.lastWatchedDate, \.watchedDate]
        guard let allEpisodes = try? context.fetch(descriptor) else { return }

        let watchedEpisodes = allEpisodes.filter { $0.isWatched }
        guard !watchedEpisodes.isEmpty else { return }

        // Group by (showID, seasonNumber)
        var episodesByShowSeason: [String: [TVEpisode]] = [:]
        for ep in watchedEpisodes {
            guard let showID = ep.showID else { continue }
            let key = "\(showID)_\(ep.seasonNumber)"
            episodesByShowSeason[key, default: []].append(ep)
        }

        let recentCutoff = Date().addingTimeInterval(-2 * 3600) // Marked in the last 2 hours
        var updatedCount = 0

        for (_, list) in episodesByShowSeason {
            let sorted = list.sorted { $0.episodeNumber < $1.episodeNumber }
            for (idx, ep) in sorted.enumerated() where idx > 0 {
                // If this episode has a recent watch date, but the preceding episode has an older historical watch date
                if let epDate = ep.lastWatchedDate, epDate > recentCutoff {
                    let prevEp = sorted[idx - 1]
                    if let prevDate = prevEp.lastWatchedDate, prevDate <= recentCutoff {
                        ep.lastWatchedDate = prevDate
                        ep.watchedDate = prevDate
                        updatedCount += 1
                    }
                }
            }
        }

        if updatedCount > 0 {
            do {
                try context.save()
                AppLogger.info("📅 Reconciled \(updatedCount) split 2-part episode watch dates with their preceding parts.", logger: AppLogger.background)
                await MainActor.run { MediaStateService.shared.postMediaStateChanged() }
            } catch {
                AppLogger.error("📅 Split episode watch date migration failed to save: \(error)", logger: AppLogger.background)
                return
            }
        }

        UserDefaults.standard.set(true, forKey: flag)
    }
}

