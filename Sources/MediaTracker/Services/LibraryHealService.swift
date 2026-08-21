import Foundation
import SwiftData

// Library heal — duplicate merge, orphan repair, searchable-text migration,
// and stale search-cache purging. Extension of the shared BackgroundDataService
// actor; `lastHealedDate` lives on the actor itself.

extension BackgroundDataService {
    func performLibraryHeal() async throws {
        let isAsleep = await SleepManager.shared.isAsleep
        guard !isAsleep else { return }
        if let lastHealed = lastHealedDate, Date().timeIntervalSince(lastHealed) < 300 {
            AppLogger.debug("⏭️ Skipping library heal — last heal was \(Int(Date().timeIntervalSince(lastHealed)))s ago", logger: AppLogger.background)
            return
        }
        lastHealedDate = Date()

        // 1. Repair Orphaned Entities
        try await repairOrphanedEntities()
        
        // 1.5. Purge stale search cache entries (older than 7 days)
        await purgeStaleSearchCache()

        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = MediaItem.thumbnailProperties
        descriptor.fetchLimit = 100
        
        var offset = 0
        var processedCount = 0
        var hasMore = true
        
        while hasMore {
            descriptor.fetchOffset = offset
            let items = try modelContext.fetch(descriptor)
            hasMore = items.count == 100
            
            // 2. Deduplicate and Standardize
            for item in items {
            if Task.isCancelled { break }
            if isThermalThrottled {
                AppLogger.warning("🌡️ Thermal throttle during library heal. Stopping early.", logger: AppLogger.background)
                hasMore = false
                break
            }
            // Migrate legacy IDs
            if !item.id.contains("_") {
                let typePrefix = item.type == .movie ? "movie" : "tv"
                item.id = "\(typePrefix)_\(item.id)"
            }

            if let tmdbIDString = item.id.split(separator: "_").last, let tmdbID = Int(tmdbIDString) {
                if let tv = item.tvShowDetails {
                    // 0. Reattach any orphaned seasons (tvShowDetails == nil) to this show,
                    // so imported/restored shows don't end up with empty season lists.
                    let orphanDesc = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID == tmdbID })
                    if let candidates = try? modelContext.fetch(orphanDesc) {
                        let orphans = candidates.filter { $0.tvShowDetails == nil }
                        if !orphans.isEmpty {
                            for season in orphans {
                                season.tvShowDetails = tv
                            }
                            AppLogger.info("🔗 Reattached \(orphans.count) orphaned seasons for \(item.title)", logger: AppLogger.background)
                        }
                    }

                    // 1. Standardize Seasons and Episodes first
                    let liveSeasons = tv.seasons.liveModels
                    for season in liveSeasons {
                        season.showID = tmdbID
                        if season.uniqueID == nil {
                            season.uniqueID = "\(tmdbID)_\(season.seasonNumber)"
                        }
                        
                        let liveEps = season.episodes.liveModels
                        for episode in liveEps {
                            episode.showID = tmdbID
                            if episode.uniqueID == nil {
                                episode.uniqueID = "\(tmdbID)_\(season.seasonNumber)_\(episode.episodeNumber)"
                            }
                            if episode.airDateValue == nil {
                                episode.updateAirDateValue()
                            }
                        }
                    }

                    // 2. Auto-mark unwatched episodes if Completed
                    let autoMark = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoMarkEpisodesWatched.rawValue)
                    if autoMark && item.stateValue == "Completed" {
                        let liveEps = liveSeasons.flatMap { $0.episodes.liveModels }
                        for ep in liveEps where !ep.isWatched {
                            ep.markWatched(true)
                        }
                    }

                    // 3. Refresh network info and creators from TMDB only if missing
                    let networkWasNil = tv.network == nil
                    let creatorsMissing = tv.creators.isEmpty
                    if tv.network == nil || tv.networkLogoPath == nil || creatorsMissing {
                        if let netDetails = try? await APIClient.shared.fetchTVDetails(tmdbID: tmdbID, force: false) {
                            if tv.network == nil { tv.network = netDetails.network }
                            if tv.networkLogoPath == nil { tv.networkLogoPath = netDetails.networkLogoPath }
                            if creatorsMissing { tv.creators = netDetails.creators.map { $0.name } }

                            // Episode gap detection: if TMDB reports more episodes than stored, trigger refresh
                            for seasonBrief in netDetails.seasons where seasonBrief.episode_count > 0 {
                                let sUID = "\(tmdbID)_\(seasonBrief.season_number)"
                                let sDesc = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.uniqueID == sUID })
                                if let existingSeason = try? modelContext.fetch(sDesc).first,
                                   existingSeason.episodes.count < seasonBrief.episode_count {
                                    _ = await self.refreshTVShow(id: item.id, tmdbID: tmdbID, metadataOnly: false, force: false)
                                    break
                                }
                            }
                        }
                    }
                    // If network was just populated, re-heal episode air dates
                    if networkWasNil && tv.network != nil {
                        for season in liveSeasons {
                            for episode in season.episodes.liveModels {
                                episode.updateAirDateValue()
                            }
                        }
                    }

                    // 4. Single recalculate at the end (was 3 separate calls)
                    tv.recalculateCachedProperties(triggerSync: true, force: true)

                    // 5. Heal: keep lastInteractionDate in sync with the most recent episode watch,
                    // so "Recently Watched" reflects real watch times.
                    if let latestWatch = liveSeasons
                        .flatMap({ $0.episodes.liveModels })
                        .compactMap({ $0.lastWatchedDate })
                        .max(),
                       latestWatch > (item.lastInteractionDate ?? .distantPast) {
                        item.lastInteractionDate = latestWatch
                    }
                }
            }
            
            item.syncCachedProperties(dirty: [.progress, .badge, .metadata, .cast])
            processedCount += 1
            }
            
            // Save after each batch
            if processedCount % 100 == 0 {
                await BadgeEngine.flushBadgeChanges(container: modelContext.container)
                try modelContext.save()
                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms between batches
            }
            
            offset += 100
        }
        
        // Final save
        await BadgeEngine.flushBadgeChanges(container: modelContext.container)
        try modelContext.save()
        
        // Phase 7: Global Notification Resync
        // After healing metadata and cached properties, ensure the system notification queue is up to date.
        await NotificationManager.shared.scheduleAllUpcomingNotifications()
        
        // Full recount to fix any drift from concurrent onBadgeChanged tasks
        let sync = DiscoverySyncService(modelContainer: modelContext.container)
        await sync.syncLibrary(force: false)
        
        // Broadcast so UI refreshes with healed data
        await MainActor.run {
            MediaStateService.shared.postMediaStateChanged()
        }
        
        AppLogger.info("✅ Maintenance: Library heal complete.", logger: AppLogger.background)
    }

    /// One-time migration: rebuild `searchableText` so localized language names are searchable.
    func performSearchableLanguageMigration() async throws {
        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = MediaItem.thumbnailProperties
        descriptor.fetchLimit = 100

        var offset = 0
        var processedCount = 0
        var hasMore = true

        while hasMore {
            descriptor.fetchOffset = offset
            let items = try modelContext.fetch(descriptor)
            hasMore = items.count == 100

            for item in items {
                if Task.isCancelled { return }
                item.syncCachedProperties(dirty: .searchable)
            }

            processedCount += items.count
            try modelContext.save()
            offset += 100
            AppLogger.debug("♻️ Searchable language migration: \(processedCount) items processed", logger: AppLogger.background)
        }
    }

    private func repairOrphanedEntities() async throws {
        let batchSize = 500
        // TVShowDetails map is retained in full — required to detect duplicates
        // and as the parent lookup for season repair. Seasons and episodes are
        // processed in batches without accumulating arrays.
        let tvDetailsDesc = FetchDescriptor<TVShowDetails>()
        let allTVDetails = try modelContext.fetch(tvDetailsDesc)

        // Group TVShowDetails by tmdbID to find duplicates
        var grouped: [Int: [TVShowDetails]] = [:]
        for details in allTVDetails {
            grouped[details.tmdbID, default: []].append(details)
        }

        var tvMap: [Int: TVShowDetails] = [:]
        for (tmdbID, duplicates) in grouped {
            if duplicates.count == 1 {
                tvMap[tmdbID] = duplicates[0]
                continue
            }

            // Multiple TVShowDetails for the same tmdbID — find the primary (most complete)
            AppLogger.warning("🔍 Found \(duplicates.count) TVShowDetails duplicates for tmdbID=\(tmdbID)", logger: AppLogger.background)

            // Score each duplicate: seasons, cast, item relationship
            var best: (index: Int, score: Int) = (0, 0)
            for (i, d) in duplicates.enumerated() {
                var score = 0
                let liveSeasons = d.seasons.liveModels
                score += liveSeasons.count * 10
                score += d.cast.liveModels.count * 5
                if d.nextEpisodeDate != nil { score += 3 }
                if d.status != nil { score += 1 }

                // Confirm item relationship via direct fetch (not relying on faulting)
                if let context = d.modelContext {
                    let itemDesc = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == "tv_\(tmdbID)" || $0.id == "\(tmdbID)" })
                    if let item = try? context.fetch(itemDesc).first {
                        // Verify the relationship points back
                        if item.tvShowDetails?.persistentModelID == d.persistentModelID {
                            score += 50
                        }
                    }
                }

                if score > best.score {
                    best = (i, score)
                }
            }

            let primary = duplicates[best.index]
            tvMap[tmdbID] = primary

            // Merge data from secondary duplicates into primary, then delete secondaries
            for (i, secondary) in duplicates.enumerated() where i != best.index {
                let liveSeasons = secondary.seasons.liveModels
                for season in liveSeasons {
                    if season.tvShowDetails?.persistentModelID != primary.persistentModelID {
                        season.tvShowDetails = primary
                    }
                    if !primary.seasons.contains(where: { $0.persistentModelID == season.persistentModelID }) {
                        primary.seasons.append(season)
                    }
                }

                let liveCast = secondary.cast.liveModels
                for member in liveCast {
                    if member.tvShowDetails?.persistentModelID != primary.persistentModelID {
                        member.tvShowDetails = primary
                    }
                }

                // Transfer item relationship if primary doesn't have one
                if primary.item == nil, let attachedItem = secondary.item {
                    attachedItem.tvShowDetails = primary
                }

                modelContext.delete(secondary)
                AppLogger.info("🧹 Merged and deleted duplicate TVShowDetails for tmdbID=\(tmdbID)", logger: AppLogger.background)
            }
        }

        // Season pass: batched fetch, repair orphan links per batch, and build the
        // (showID, seasonNumber) → TVSeason lookup needed by the episode pass.
        // No seasons are inserted or deleted here, so offset pagination is stable.
        var seasonMap: [Int: [Int: TVSeason]] = [:]
        var seasonOffset = 0
        while true {
            var sDesc = FetchDescriptor<TVSeason>()
            sDesc.fetchLimit = batchSize
            sDesc.fetchOffset = seasonOffset
            let batch = try modelContext.fetch(sDesc)
            for season in batch {
                if season.tvShowDetails == nil, let showID = season.showID, let parent = tvMap[showID] {
                    season.tvShowDetails = parent
                }
                guard let showID = season.showID else { continue }
                seasonMap[showID, default: [:]][season.seasonNumber] = season
            }
            if batch.count < batchSize { break }
            seasonOffset += batchSize
        }
        try modelContext.save()

        // Episode pass: batched fetch, repair per batch, save per batch —
        // never materializes the full episode table.
        var epOffset = 0
        while true {
            var eDesc = FetchDescriptor<TVEpisode>()
            eDesc.fetchLimit = batchSize
            eDesc.fetchOffset = epOffset
            let batch = try modelContext.fetch(eDesc)
            for episode in batch {
                if episode.season == nil, let showID = episode.showID, let parentSeason = seasonMap[showID]?[episode.seasonNumber] {
                    episode.season = parentSeason
                }
            }
            if batch.count < batchSize { break }
            try modelContext.save()
            epOffset += batchSize
        }
        try modelContext.save()
    }
    
    private func purgeStaleSearchCache() async {
        let sevenDaysAgo = Date().addingTimeInterval(-.days7)
        let descriptor = FetchDescriptor<SearchCacheEntity>(
            predicate: #Predicate { $0.timestamp < sevenDaysAgo }
        )
        if let staleEntries = try? modelContext.fetch(descriptor), !staleEntries.isEmpty {
            for entry in staleEntries {
                modelContext.delete(entry)
            }
            try? modelContext.save()
            AppLogger.info("🧹 Purged \(staleEntries.count) stale search cache entries", logger: AppLogger.background)
        }
    }
}
