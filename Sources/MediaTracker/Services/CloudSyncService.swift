import Foundation
import SwiftData

/// High-performance, zero-dependency cloud sync client for Supabase PostgREST.
/// Operates completely via native `URLSession` to keep MediaTracker lean and fast.
@ModelActor
actor CloudSyncService {
    static var supabaseURL: String {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudSyncURL.rawValue)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static var supabaseAnonKey: String {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudSyncAnonKey.rawValue)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let fallbackISO8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private func parseISO8601(_ string: String?) -> Date? {
        guard let string else { return nil }
        return iso8601Formatter.date(from: string) ?? fallbackISO8601Formatter.date(from: string)
    }

    // MARK: - Secret Sync Key Helpers

    /// Returns the active secret sync key, or generates a fresh high-entropy key if none exists.
    static func getOrGenerateSyncKey() -> String {
        if let existing = UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudSyncKey.rawValue),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }
        let fresh = "mt_sync_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16).lowercased()
        UserDefaults.standard.set(fresh, forKey: UserDefaultsKeys.cloudSyncKey.rawValue)
        return fresh
    }

    // MARK: - Public Two-Way Sync & Backup Entrypoints

    struct ImpactTitleItem: Identifiable, Sendable, Equatable {
        var id: String
        var title: String
        var type: String
        var state: String
        var taste: String
        var posterURL: String?
        var conflictCloudState: String?
        var conflictCloudTaste: String?

        var isConflict: Bool {
            conflictCloudState != nil || conflictCloudTaste != nil
        }
    }

    struct ImpactEpisodeShow: Identifiable, Sendable, Equatable {
        var id: String
        var title: String
        var posterURL: String?
        var episodeCount: Int
    }

    struct SyncImpact: Sendable {
        var titlesToImport: [ImpactTitleItem] = []
        var titlesToUpdate: [ImpactTitleItem] = []
        var titlesToUpload: [ImpactTitleItem] = []
        var episodesToImportShows: [ImpactEpisodeShow] = []
        var episodesToUploadShows: [ImpactEpisodeShow] = []
        var totalEpisodesToImport: Int = 0
        var totalEpisodesToUpload: Int = 0
        var collectionsToImport: [ImpactCollection] = []
        var collectionsToUpload: [ImpactCollection] = []
        /// Watch history: local cycles/events the cloud doesn't have yet.
        var cyclesToUpload: Int = 0
        var eventsToUpload: Int = 0
        var errorDescription: String? = nil

        var totalChanges: Int {
            titlesToImport.count + titlesToUpdate.count + titlesToUpload.count +
                totalEpisodesToImport + totalEpisodesToUpload +
                collectionsToImport.count + collectionsToUpload.count +
                cyclesToUpload + eventsToUpload
        }

        var hasChanges: BooleanLiteralType {
            totalChanges > 0
        }
    }

    struct ImpactCollection: Identifiable, Sendable, Equatable {
        var id: String
        var name: String
        var itemCount: Int
    }

    struct SyncSummary: Sendable {
        var mediaPushed: Int = 0
        var mediaPulled: Int = 0
        var episodesPushed: Int = 0
        var episodesPulled: Int = 0
        var collectionsPushed: Int = 0
        var collectionsPulled: Int = 0
        var collectionItemsPushed: Int = 0
        var collectionItemsPulled: Int = 0
        var cyclesPushed: Int = 0
        var cyclesPulled: Int = 0
        var eventsPushed: Int = 0
        var eventsPulled: Int = 0
        var errorDescription: String? = nil
    }

    /// Dry run impact calculation without mutating SwiftData or Supabase
    func calculateSyncImpact() async -> SyncImpact {
        guard !Self.supabaseURL.isEmpty else {
            return SyncImpact(errorDescription: "Missing Supabase Project URL")
        }
        guard !Self.supabaseAnonKey.isEmpty else {
            return SyncImpact(errorDescription: "Missing Supabase Anon/API Key")
        }
        let syncKey = Self.getOrGenerateSyncKey()
        guard !syncKey.isEmpty else {
            return SyncImpact(errorDescription: "Missing Sync Key")
        }

        var impact = SyncImpact()
        let lastSyncTimestamp = UserDefaults.standard.double(forKey: UserDefaultsKeys.cloudSyncLastTimestamp.rawValue)
        let watermark = UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudSyncWatermark.rawValue)

        do {
            // 1. Fetch remote media (paginated: a single GET truncates at 1000 rows)
            let remoteItems = try await fetchRemoteMedia(syncKey: syncKey, since: watermark)
            let remoteMap = Dictionary(remoteItems.map { ($0.media_id, $0) }, uniquingKeysWith: { first, _ in first })

            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.propertiesToFetch = [\.id, \.title, \.typeValue, \.stateValue, \.tasteValue, \.posterURL, \.customPosterURL, \.isSoftDeleted, \.lastUpdated, \.lastStateChangeDate, \.lastInteractionDate]
            let localItems = (try? modelContext.fetch(descriptor)) ?? []
            let localMap = Dictionary(localItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            for remote in remoteItems {
                if let local = localMap[remote.media_id] {
                    // A differing state/taste *or* a differing soft-delete is a difference.
                    let differs = local.stateValue != remote.state
                        || local.tasteValue != remote.taste
                        || local.isSoftDeleted != remote.is_soft_deleted
                    if differs {
                        // Same rule the sync itself uses: newest edit wins. A "like"/"loved"
                        // change only shows as a cloud update when the cloud copy is actually
                        // newer; otherwise it's this device's upload — not a conflict. The old
                        // version flagged every taste difference as a conflict regardless.
                        let remoteTime = parseISO8601(remote.updated_at) ?? .distantPast
                        if remoteTime > local.syncEditTime {
                            impact.titlesToUpdate.append(
                                ImpactTitleItem(
                                    id: local.id,
                                    title: local.title,
                                    type: local.typeValue,
                                    state: local.stateValue,
                                    taste: local.tasteValue,
                                    posterURL: local.customPosterURL ?? local.posterURL,
                                    conflictCloudState: remote.state,
                                    conflictCloudTaste: remote.taste
                                )
                            )
                        } else {
                            impact.titlesToUpload.append(
                                ImpactTitleItem(
                                    id: local.id,
                                    title: local.title,
                                    type: local.typeValue,
                                    state: local.stateValue,
                                    taste: local.tasteValue,
                                    posterURL: local.customPosterURL ?? local.posterURL
                                )
                            )
                        }
                    }
                } else {
                    impact.titlesToImport.append(
                        ImpactTitleItem(
                            id: remote.media_id,
                            title: remote.media_id,
                            type: remote.type,
                            state: remote.state,
                            taste: remote.taste,
                            posterURL: remote.custom_poster_url
                        )
                    )
                }
            }

            for local in localItems {
                if remoteMap[local.id] == nil {
                    impact.titlesToUpload.append(
                        ImpactTitleItem(
                            id: local.id,
                            title: local.title,
                            type: local.typeValue,
                            state: local.stateValue,
                            taste: local.tasteValue,
                            posterURL: local.customPosterURL ?? local.posterURL
                        )
                    )
                } else if local.syncEditTime.timeIntervalSince1970 > lastSyncTimestamp,
                          !impact.titlesToUpdate.contains(where: { $0.id == local.id }),
                          !impact.titlesToUpload.contains(where: { $0.id == local.id }) {
                    impact.titlesToUpload.append(
                        ImpactTitleItem(
                            id: local.id,
                            title: local.title,
                            type: local.typeValue,
                            state: local.stateValue,
                            taste: local.tasteValue,
                            posterURL: local.customPosterURL ?? local.posterURL
                        )
                    )
                }
            }

            // 2. Fetch remote episodes (paginated: a single GET truncates at 1000 rows)
            let remoteEps = try await fetchRemoteEpisodes(syncKey: syncKey, since: watermark)
            let remoteEpMap = Dictionary(remoteEps.map { ($0.episode_id, $0.is_watched) }, uniquingKeysWith: { first, _ in first })

            var epDescriptor = FetchDescriptor<TVEpisode>()
            epDescriptor.propertiesToFetch = [\.uniqueID, \.isWatched, \.showID, \.seasonNumber, \.episodeNumber]
            let localEpisodes = (try? modelContext.fetch(epDescriptor)) ?? []

            var mediaDescriptor = FetchDescriptor<MediaItem>()
            mediaDescriptor.propertiesToFetch = [\.id, \.title, \.posterURL, \.customPosterURL]
            let allMedia = (try? modelContext.fetch(mediaDescriptor)) ?? []
            let mediaByNumericID: [Int: MediaItem] = Dictionary(
                allMedia.compactMap { item in
                    guard let num = Int(item.id.split(separator: "_").last ?? "") else { return nil }
                    return (num, item)
                },
                uniquingKeysWith: { first, _ in first }
            )

            var importCountsByShow: [Int: Int] = [:]
            var uploadCountsByShow: [Int: Int] = [:]

            for lEp in localEpisodes {
                guard let uid = lEp.uniqueID, let showID = lEp.showID else { continue }
                if let rWatched = remoteEpMap[uid] {
                    if lEp.isWatched != rWatched {
                        importCountsByShow[showID, default: 0] += 1
                        impact.totalEpisodesToImport += 1
                    }
                } else if lEp.isWatched {
                    uploadCountsByShow[showID, default: 0] += 1
                    impact.totalEpisodesToUpload += 1
                }
            }

            impact.episodesToImportShows = importCountsByShow.map { (showID, count) in
                let media = mediaByNumericID[showID]
                return ImpactEpisodeShow(
                    id: "tv_\(showID)",
                    title: media?.title ?? "Show #\(showID)",
                    posterURL: media?.customPosterURL ?? media?.posterURL,
                    episodeCount: count
                )
            }.sorted { $0.episodeCount > $1.episodeCount }

            impact.episodesToUploadShows = uploadCountsByShow.map { (showID, count) in
                let media = mediaByNumericID[showID]
                return ImpactEpisodeShow(
                    id: "tv_\(showID)",
                    title: media?.title ?? "Show #\(showID)",
                    posterURL: media?.customPosterURL ?? media?.posterURL,
                    episodeCount: count
                )
            }.sorted { $0.episodeCount > $1.episodeCount }

            // 3. Collections (rows + membership), so the sheet actually mentions them.
            let remoteCollections = try await fetchRemoteCollections(syncKey: syncKey, since: watermark)
            // Unwatermarked (it is only ~25 rows): the membership push tests "does the cloud
            // have this row?", and a watermarked response omits unchanged rows — which reads
            // the same as missing and re-pushed every membership on every sync.
            let remoteCollectionItems = try await fetchRemoteCollectionItems(syncKey: syncKey)
            let remoteCollectionByID = Dictionary(remoteCollections.map { ($0.collection_id, $0) }, uniquingKeysWith: { first, _ in first })
            let remoteItemCounts = Dictionary(grouping: remoteCollectionItems.filter { !$0.is_deleted }, by: \.collection_id)
                .mapValues { $0.count }
            let localCollections = (try? modelContext.fetch(FetchDescriptor<MediaCollection>())) ?? []
            let localCollectionIDs = Set(localCollections.map { $0.id.uuidString })

            for local in localCollections {
                let impactItem = ImpactCollection(id: local.id.uuidString, name: local.name, itemCount: local.items.count)
                guard let remote = remoteCollectionByID[local.id.uuidString] else {
                    impact.collectionsToUpload.append(impactItem)
                    continue
                }
                let differs = local.name != remote.name
                    || local.systemImage != remote.system_image
                    || (local.notes ?? "") != (remote.notes ?? "")
                    || local.isPinned != remote.is_pinned
                    || local.completedItemIDs != remote.completed_item_ids
                    || (local.smartRulesData.flatMap { String(data: $0, encoding: .utf8) }) != remote.smart_rules
                let remoteTime = parseISO8601(remote.updated_at) ?? .distantPast
                if differs, (local.updatedAt ?? .distantPast) > remoteTime {
                    impact.collectionsToUpload.append(impactItem)
                }
            }
            for remote in remoteCollections where !remote.is_deleted {
                if !localCollectionIDs.contains(remote.collection_id) {
                    impact.collectionsToImport.append(
                        ImpactCollection(
                            id: remote.collection_id,
                            name: remote.name,
                            itemCount: remoteItemCounts[remote.collection_id] ?? 0
                        )
                    )
                }
            }

            // 4. Watch history: only ids are needed to count what the cloud is missing.
            let remoteCycleIDRows: [RemoteID] = try await fetchAllPages(
                endpoint: "user_watch_cycles",
                query: "user_id=eq.\(syncKey)&select=cycle_id",
                syncKey: syncKey
            )
            let remoteEventIDRows: [RemoteID] = try await fetchAllPages(
                endpoint: "user_watch_events",
                query: "user_id=eq.\(syncKey)&select=event_id",
                syncKey: syncKey
            )
            let remoteCycleIDs = Set(remoteCycleIDRows.compactMap { $0.cycle_id })
            let remoteEventIDs = Set(remoteEventIDRows.compactMap { $0.event_id })
            let localCycles = (try? modelContext.fetch(FetchDescriptor<WatchCycle>())) ?? []
            let localEvents = (try? modelContext.fetch(FetchDescriptor<WatchEvent>())) ?? []
            impact.cyclesToUpload = localCycles.filter { !remoteCycleIDs.contains($0.id.uuidString) }.count
            impact.eventsToUpload = localEvents.filter { !remoteEventIDs.contains($0.id.uuidString) }.count
        } catch {
            impact.errorDescription = error.localizedDescription
        }

        return impact
    }

    /// Backs up the entire local library (all titles and watched episodes) to Supabase in batches.
    func backupToCloud() async -> SyncSummary {
        guard !Self.supabaseURL.isEmpty else {
            return SyncSummary(errorDescription: "Missing Supabase Project URL")
        }
        guard !Self.supabaseAnonKey.isEmpty else {
            return SyncSummary(errorDescription: "Missing Supabase Anon/API Key")
        }
        let syncKey = Self.getOrGenerateSyncKey()
        guard !syncKey.isEmpty else {
            return SyncSummary(errorDescription: "Missing Sync Key")
        }

        var summary = SyncSummary()
        let now = Date().timeIntervalSince1970

        do {
            // Force push all media items (since: 0 pushes all items)
            summary.mediaPushed = try await pushMediaItems(syncKey: syncKey, since: 0)

            // Force push all watched episodes (since: 0 pushes all watched)
            summary.episodesPushed = try await pushEpisodes(syncKey: syncKey, since: 0)

            // Collections too — an empty remote map makes every local collection "missing"
            // and so gets pushed, and the same for its membership rows.
            summary.collectionsPushed = try await pushCollections(syncKey: syncKey, remoteById: [:])
            summary.collectionItemsPushed = try await pushCollectionItems(syncKey: syncKey, remote: [])

            // ...and the whole watch history (empty remote maps => everything is pushed).
            summary.cyclesPushed = try await pushWatchCycles(syncKey: syncKey, remoteById: [:])
            summary.eventsPushed = try await pushWatchEvents(syncKey: syncKey, remoteById: [:])

            UserDefaults.standard.set(now, forKey: UserDefaultsKeys.cloudSyncLastTimestamp.rawValue)
            try? modelContext.save()
        } catch {
            summary.errorDescription = error.localizedDescription
            AppLogger.error("backupToCloud failed: \(error.localizedDescription)", logger: AppLogger.sync)
        }

        return summary
    }

    /// Selective Two-Way Sync with user-approved selections.
    func performSelectiveSync(
        approvedImportIDs: Set<String>,
        approvedUpdateIDs: Set<String>,
        approvedUploadIDs: Set<String>,
        syncEpisodes: Bool
    ) async -> SyncSummary {
        guard !Self.supabaseURL.isEmpty else {
            return SyncSummary(errorDescription: "Missing Supabase Project URL")
        }
        guard !Self.supabaseAnonKey.isEmpty else {
            return SyncSummary(errorDescription: "Missing Supabase Anon/API Key")
        }
        let syncKey = Self.getOrGenerateSyncKey()
        guard !syncKey.isEmpty else {
            return SyncSummary(errorDescription: "Missing Sync Key")
        }

        var summary = SyncSummary()
        let lastSyncTimestamp = UserDefaults.standard.double(forKey: UserDefaultsKeys.cloudSyncLastTimestamp.rawValue)
        // Incremental pulls: only ask for rows newer than the last sync's newest stamp.
        let watermark = UserDefaults.standard.string(forKey: UserDefaultsKeys.cloudSyncWatermark.rawValue)
        let now = Date().timeIntervalSince1970

        do {
            // 1. Push approved local titles
            let descriptor = FetchDescriptor<MediaItem>()
            let localItems = try modelContext.fetch(descriptor)
            // `date_added` is immutable, so a cloud row without one is a gap to fill rather
            // than a change to review — and a title that already exists remotely is never in
            // the "changed since last sync" upload set, so it would otherwise stay NULL there
            // forever. Backfill it silently so the other device can order "Recently Added".
            // Deliberately *not* watermarked: this is an existence test ("does the cloud hold a
            // date_added for this id?"). A watermarked response omits unchanged rows, and
            // "omitted" is indistinguishable from "missing" — which re-pushed the whole
            // library as needing a backfill.
            let remoteDateAdded = try await fetchRemoteDateAdded(syncKey: syncKey)
            let itemsToUpload = localItems.filter { item in
                approvedUploadIDs.contains(item.id) ||
                    (item.dateAdded != nil && remoteDateAdded[item.id] == nil)
            }
            if !itemsToUpload.isEmpty {
                let chunkSize = 100
                for chunk in stride(from: 0, to: itemsToUpload.count, by: chunkSize) {
                    let slice = Array(itemsToUpload[chunk..<min(chunk + chunkSize, itemsToUpload.count)])
                    let payloads = slice.map { item in
                        RemoteMediaItem(
                            user_id: syncKey,
                            media_id: item.id,
                            type: item.typeValue,
                            state: item.stateValue,
                            taste: item.tasteValue,
                            custom_poster_url: item.customPosterURL,
                            is_soft_deleted: item.isSoftDeleted,
                            last_interaction_date: item.lastInteractionDate.map { iso8601Formatter.string(from: $0) },
                            last_state_change_date: item.lastStateChangeDate.map { iso8601Formatter.string(from: $0) },
                            date_added: item.dateAdded.map { iso8601Formatter.string(from: $0) },
                            updated_at: iso8601Formatter.string(from: Date())
                        )
                    }
                    try await postRemote(endpoint: "user_media", syncKey: syncKey, body: payloads)
                    summary.mediaPushed += slice.count
                }
            }

            // 2. Pull approved remote titles
            let allowedPullIDs = approvedImportIDs.union(approvedUpdateIDs)
            if !allowedPullIDs.isEmpty {
                summary.mediaPulled = try await pullMediaItems(syncKey: syncKey, filterIDs: allowedPullIDs, since: watermark)
            }

            // 3. Episodes sync
            if syncEpisodes {
                summary.episodesPushed = try await pushEpisodes(syncKey: syncKey, since: lastSyncTimestamp)
                summary.episodesPulled = try await pullEpisodes(syncKey: syncKey, since: watermark)
            }

            // 4. Collections (rows + membership). The sheet has no per-collection approval —
            //    they're few and low-risk, so reconcile wholesale (newest wins). Without this
            //    the normal "Sync Now" flow never pushed collections at all.
            let remoteCollections = try await fetchRemoteCollections(syncKey: syncKey, since: watermark)
            let remoteCollectionItems = try await fetchRemoteCollectionItems(syncKey: syncKey, since: watermark)
            summary.collectionsPushed = try await pushCollections(
                syncKey: syncKey,
                remoteById: Dictionary(remoteCollections.map { ($0.collection_id, $0) }, uniquingKeysWith: { first, _ in first })
            )
            summary.collectionsPulled = try await applyRemoteCollections(remoteCollections)
            summary.collectionItemsPushed = try await pushCollectionItems(syncKey: syncKey, remote: remoteCollectionItems)
            summary.collectionItemsPulled = try await applyRemoteCollectionItems(remoteCollectionItems)

            // 5. Watch history: the cycles that group a viewing plus the events that are the
            //    actual timeline, so rewatches and "when did I watch this" survive the trip.
            let remoteCycles = try await fetchRemoteWatchCycles(syncKey: syncKey, since: watermark)
            let remoteEvents = try await fetchRemoteWatchEvents(syncKey: syncKey, since: watermark)
            summary.cyclesPushed = try await pushWatchCycles(
                syncKey: syncKey,
                remoteById: Dictionary(remoteCycles.map { ($0.cycle_id, $0) }, uniquingKeysWith: { first, _ in first }),
                watermark: watermark
            )
            summary.cyclesPulled = try await applyRemoteWatchCycles(remoteCycles)
            summary.eventsPushed = try await pushWatchEvents(
                syncKey: syncKey,
                remoteById: Dictionary(remoteEvents.map { ($0.event_id, $0) }, uniquingKeysWith: { first, _ in first }),
                watermark: watermark
            )
            summary.eventsPulled = try await applyRemoteWatchEvents(remoteEvents)

            UserDefaults.standard.set(now, forKey: UserDefaultsKeys.cloudSyncLastTimestamp.rawValue)
            // Advance the incremental pull watermark so the next sync only asks for changes.
            if let advanced = newWatermark {
                UserDefaults.standard.set(advanced, forKey: UserDefaultsKeys.cloudSyncWatermark.rawValue)
            }
            try? modelContext.save()
        } catch {
            summary.errorDescription = error.localizedDescription
            AppLogger.error("performSelectiveSync failed: \(error.localizedDescription)", logger: AppLogger.sync)
        }

        return summary
    }

    func performSync() async -> SyncSummary {
        guard !Self.supabaseURL.isEmpty else {
            return SyncSummary(errorDescription: "Missing Supabase Project URL")
        }
        guard !Self.supabaseAnonKey.isEmpty else {
            return SyncSummary(errorDescription: "Missing Supabase Anon/API Key")
        }

        let syncKey = Self.getOrGenerateSyncKey()
        guard !syncKey.isEmpty else {
            return SyncSummary(errorDescription: "Missing Sync Key")
        }

        var summary = SyncSummary()

        do {
            // Reconcile against the cloud, resolving every row by edit time (newest wins) —
            // the same rule Android's CloudSyncManager uses. The previous order pushed local
            // changes unconditionally and then overwrote local with whatever the cloud had,
            // so a macOS sync could silently clobber a newer edit made on another device, and
            // a soft-delete was never propagated.
            let remoteMedia = try await fetchRemoteMedia(syncKey: syncKey)
            let remoteEpisodes = try await fetchRemoteEpisodes(syncKey: syncKey)

            summary.mediaPushed = try await pushMediaItems(
                syncKey: syncKey,
                remoteById: Dictionary(remoteMedia.map { ($0.media_id, $0) }, uniquingKeysWith: { first, _ in first })
            )
            summary.mediaPulled = try await applyRemoteMedia(remoteMedia)

            summary.episodesPushed = try await pushEpisodes(
                syncKey: syncKey,
                remoteById: Dictionary(remoteEpisodes.map { ($0.episode_id, $0) }, uniquingKeysWith: { first, _ in first })
            )
            summary.episodesPulled = try await applyRemoteEpisodes(remoteEpisodes)

            // Collections: the collection rows plus their membership (a join table), so a
            // collection created or edited on either device shows up on the other.
            let remoteCollections = try await fetchRemoteCollections(syncKey: syncKey)
            let remoteCollectionItems = try await fetchRemoteCollectionItems(syncKey: syncKey)

            summary.collectionsPushed = try await pushCollections(
                syncKey: syncKey,
                remoteById: Dictionary(remoteCollections.map { ($0.collection_id, $0) }, uniquingKeysWith: { first, _ in first })
            )
            summary.collectionsPulled = try await applyRemoteCollections(remoteCollections)
            summary.collectionItemsPushed = try await pushCollectionItems(
                syncKey: syncKey,
                remote: remoteCollectionItems
            )
            summary.collectionItemsPulled = try await applyRemoteCollectionItems(remoteCollectionItems)

            // Update timestamp on successful sync
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: UserDefaultsKeys.cloudSyncLastTimestamp.rawValue)
            try? modelContext.save()
        } catch {
            summary.errorDescription = error.localizedDescription
            AppLogger.error("CloudSyncService failed: \(error.localizedDescription)", logger: AppLogger.sync)
        }

        return summary
    }

    // MARK: - Media Items Push / Pull

    private struct RemoteMediaItem: Codable {
        var user_id: String
        var media_id: String
        var type: String
        var state: String
        var taste: String
        var custom_poster_url: String?
        var is_soft_deleted: Bool
        var last_interaction_date: String?
        var last_state_change_date: String?
        /// When the title joined the library. Unlike last_interaction_date it never moves, so
        /// the other device can order "Recently Added" by it (and adopt it for old rows).
        var date_added: String?
        var updated_at: String?

        enum CodingKeys: String, CodingKey {
            case user_id, media_id, type, state, taste, custom_poster_url, is_soft_deleted, last_interaction_date, last_state_change_date, date_added, updated_at
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(user_id, forKey: .user_id)
            try container.encode(media_id, forKey: .media_id)
            try container.encode(type, forKey: .type)
            try container.encode(state, forKey: .state)
            try container.encode(taste, forKey: .taste)
            try container.encode(custom_poster_url, forKey: .custom_poster_url)
            try container.encode(is_soft_deleted, forKey: .is_soft_deleted)
            try container.encode(last_interaction_date, forKey: .last_interaction_date)
            try container.encode(last_state_change_date, forKey: .last_state_change_date)
            try container.encode(date_added, forKey: .date_added)
            try container.encode(updated_at, forKey: .updated_at)
        }
    }

    private func pushMediaItems(
        syncKey: String,
        since: TimeInterval = 0,
        remoteById: [String: RemoteMediaItem]? = nil
    ) async throws -> Int {
        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = [
            \.id, \.typeValue, \.stateValue, \.tasteValue, \.customPosterURL,
            \.isSoftDeleted, \.lastInteractionDate, \.lastStateChangeDate, \.lastUpdated
        ]

        let localItems = try modelContext.fetch(descriptor)
        let dirtyItems = localItems.filter { item in
            if let remoteById {
                // Full reconcile (performSync): push only when this device's edit is newer
                // than the cloud row, or the row isn't there yet. Never overwrite a newer
                // remote edit — the old unconditional push silently clobbered edits made on
                // another device.
                guard let remote = remoteById[item.id] else { return true }
                let remoteTime = parseISO8601(remote.updated_at) ?? .distantPast
                return item.syncEditTime > remoteTime
            }
            // Watermark push. backupToCloud passes since: 0 to force-push everything.
            if since == 0 { return true }
            return item.syncEditTime.timeIntervalSince1970 > since
        }

        guard !dirtyItems.isEmpty else { return 0 }

        // Batch in groups of 100
        let chunkSize = 100
        var pushedCount = 0

        for chunk in stride(from: 0, to: dirtyItems.count, by: chunkSize) {
            let slice = Array(dirtyItems[chunk..<min(chunk + chunkSize, dirtyItems.count)])
            let payloads: [RemoteMediaItem] = slice.map { item in
                RemoteMediaItem(
                    user_id: syncKey,
                    media_id: item.id,
                    type: item.typeValue,
                    state: item.stateValue,
                    taste: item.tasteValue,
                    custom_poster_url: item.customPosterURL,
                    is_soft_deleted: item.isSoftDeleted,
                    last_interaction_date: item.lastInteractionDate.map { iso8601Formatter.string(from: $0) },
                    last_state_change_date: item.lastStateChangeDate.map { iso8601Formatter.string(from: $0) },
                    date_added: item.dateAdded.map { iso8601Formatter.string(from: $0) },
                    updated_at: iso8601Formatter.string(from: Date())
                )
            }

            try await postRemote(endpoint: "user_media", syncKey: syncKey, body: payloads)
            pushedCount += slice.count
        }

        return pushedCount
    }

    /// Applies remote media rows locally.
    ///
    /// Unless [force] is set, a row is only taken when the cloud copy is newer than the
    /// local edit (last-writer-wins) — the old code overwrote local unconditionally, so an
    /// edit made on another device could be replaced by an older cloud row. Soft-deletes
    /// count as a difference, so a delete now propagates both ways.
    private func applyRemoteMedia(
        _ rawRemoteItems: [RemoteMediaItem],
        filterIDs: Set<String>? = nil,
        force: Bool = false
    ) async throws -> Int {
        let remoteItems = rawRemoteItems.filter { item in
            guard let filter = filterIDs else { return true }
            return filter.contains(item.media_id)
        }
        guard !remoteItems.isEmpty else { return 0 }

        var pulledCount = 0
        for remote in remoteItems {
            let mediaID = remote.media_id
            let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == mediaID })
            if let existing = try? modelContext.fetch(descriptor).first {
                let differs = existing.stateValue != remote.state
                    || existing.tasteValue != remote.taste
                    || existing.isSoftDeleted != remote.is_soft_deleted
                guard differs else { continue }
                if !force {
                    let remoteTime = parseISO8601(remote.updated_at) ?? .distantPast
                    guard remoteTime > existing.syncEditTime else { continue }
                }
                existing.stateValue = remote.state
                existing.tasteValue = remote.taste
                existing.isSoftDeleted = remote.is_soft_deleted
                if let custom = remote.custom_poster_url { existing.customPosterURL = custom }
                if let interStr = remote.last_interaction_date, let d = parseISO8601(interStr) {
                    existing.lastInteractionDate = d
                }
                if let stateStr = remote.last_state_change_date, let d = parseISO8601(stateStr) {
                    existing.lastStateChangeDate = d
                }
                // Adopt the cloud's added date only when we have none: a Mac that has held the
                // title longer shouldn't have its dateAdded replaced by a later device's.
                if existing.dateAdded == nil, let addedStr = remote.date_added, let d = parseISO8601(addedStr) {
                    existing.dateAdded = d
                }
                existing.syncCachedProperties(dirty: .progress)
                if remote.state == MediaState.completedRaw {
                    // Same reason as episodes: log the watch so it appears in the history /
                    // "watched this year" (which is WatchEvent-driven).
                    WatchHistoryCoordinator.recordImportedMovie(
                        mediaID: remote.media_id,
                        watchedAt: existing.lastStateChangeDate ?? Date(),
                        runtimeMinutes: existing.cachedRuntime,
                        context: modelContext
                    )
                }
                pulledCount += 1
            } else {
                // Media title doesn't exist locally yet -> create stub and schedule metadata refresh
                let mediaType: MediaType = remote.type == "TV" ? .tvShow : .movie
                let tmdbID = Int(remote.media_id.split(separator: "_").last ?? "") ?? 0
                if tmdbID > 0 {
                    _ = await BackgroundDataService(modelContainer: modelContext.container)
                        .createNewMediaItem(
                            uniqueID: remote.media_id,
                            tmdbID: tmdbID,
                            type: mediaType,
                            title: "Importing...",
                            overview: "",
                            posterURL: nil,
                            releaseDateString: nil
                        )
                    // Apply pulled tracking state
                    if let fresh = try? modelContext.fetch(descriptor).first {
                        fresh.stateValue = remote.state
                        fresh.tasteValue = remote.taste
                        fresh.isSoftDeleted = remote.is_soft_deleted
                        // A title imported from the cloud was added *there* first.
                        if let addedStr = remote.date_added, let d = parseISO8601(addedStr) {
                            fresh.dateAdded = d
                        }
                        fresh.syncCachedProperties(dirty: .all)
                    }
                    pulledCount += 1
                }
            }
        }

        return pulledCount
    }

    /// Fetch + apply for the user-approved selective sync, which explicitly opts into the
    /// cloud copy (hence `force`).
    private func pullMediaItems(syncKey: String, filterIDs: Set<String>? = nil, since: String? = nil) async throws -> Int {
        let remote = try await fetchRemoteMedia(syncKey: syncKey, since: since)
        return try await applyRemoteMedia(remote, filterIDs: filterIDs, force: true)
    }

    // MARK: - TV Episodes Push / Pull

    private struct RemoteEpisode: Codable {
        var user_id: String
        var episode_id: String
        var show_id: String
        var season_number: Int
        var episode_number: Int
        var is_watched: Bool
        var watched_date: String?
        var updated_at: String?

        enum CodingKeys: String, CodingKey {
            case user_id, episode_id, show_id, season_number, episode_number, is_watched, watched_date, updated_at
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(user_id, forKey: .user_id)
            try container.encode(episode_id, forKey: .episode_id)
            try container.encode(show_id, forKey: .show_id)
            try container.encode(season_number, forKey: .season_number)
            try container.encode(episode_number, forKey: .episode_number)
            try container.encode(is_watched, forKey: .is_watched)
            try container.encode(watched_date, forKey: .watched_date)
            try container.encode(updated_at, forKey: .updated_at)
        }
    }

    private func pushEpisodes(
        syncKey: String,
        since: TimeInterval = 0,
        remoteById: [String: RemoteEpisode]? = nil
    ) async throws -> Int {
        let descriptor = FetchDescriptor<TVEpisode>()
        let episodes = try modelContext.fetch(descriptor)

        let dirtyEpisodes = episodes.filter { ep in
            if let remoteById {
                // Reconcile: push only when this device's watch state is newer than the
                // cloud row, or the row isn't there yet. Un-watches count as changes too.
                let epID = ep.uniqueID ?? ep.showID.map { "tv_\($0)_s\(ep.seasonNumber)_e\(ep.episodeNumber)" } ?? ""
                guard let remote = remoteById[epID] else { return ep.isWatched }
                if ep.isWatched == remote.is_watched { return false }
                let remoteTime = parseISO8601(remote.updated_at) ?? .distantPast
                return ep.syncEditTime > remoteTime
            }
            if since == 0 { return ep.isWatched }
            return ep.syncEditTime.timeIntervalSince1970 > since
        }

        guard !dirtyEpisodes.isEmpty else { return 0 }

        let chunkSize = 100
        var pushedCount = 0

        for chunk in stride(from: 0, to: dirtyEpisodes.count, by: chunkSize) {
            let slice = Array(dirtyEpisodes[chunk..<min(chunk + chunkSize, dirtyEpisodes.count)])
            let payloads: [RemoteEpisode] = slice.compactMap { ep in
                guard let showID = ep.showID else { return nil }
                let epID = ep.uniqueID ?? "tv_\(showID)_s\(ep.seasonNumber)_e\(ep.episodeNumber)"
                return RemoteEpisode(
                    user_id: syncKey,
                    episode_id: epID,
                    show_id: "tv_\(showID)",
                    season_number: ep.seasonNumber,
                    episode_number: ep.episodeNumber,
                    is_watched: ep.isWatched,
                    watched_date: ep.watchedDate.map { iso8601Formatter.string(from: $0) },
                    updated_at: iso8601Formatter.string(from: Date())
                )
            }

            try await postRemote(endpoint: "user_episodes", syncKey: syncKey, body: payloads)
            pushedCount += payloads.count
        }

        return pushedCount
    }

    /// Applies remote episode watch state locally, newest-wins unless [force] is set.
    private func applyRemoteEpisodes(_ remoteEpisodes: [RemoteEpisode], force: Bool = false) async throws -> Int {
        guard !remoteEpisodes.isEmpty else { return 0 }

        var pulledCount = 0
        for remote in remoteEpisodes {
            let epID = remote.episode_id
            let descriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.uniqueID == epID })
            if let ep = try? modelContext.fetch(descriptor).first {
                guard ep.isWatched != remote.is_watched else { continue }
                if !force {
                    let remoteTime = parseISO8601(remote.updated_at) ?? .distantPast
                    guard remoteTime > ep.syncEditTime else { continue }
                }
                ep.isWatched = remote.is_watched
                if let dateStr = remote.watched_date {
                    ep.watchedDate = parseISO8601(dateStr)
                    ep.lastWatchedDate = ep.watchedDate
                }
                if remote.is_watched {
                    // "Watched this year" reads WatchEvents, which only local mutations and
                    // imports created. A watch that arrived via sync marked the episode but
                    // never logged a WatchEvent, so its time never showed up.
                    WatchHistoryCoordinator.recordImportedEpisode(
                        mediaID: remote.show_id,
                        episodeID: remote.episode_id,
                        watchedAt: ep.watchedDate ?? ep.lastWatchedDate ?? Date(),
                        runtimeMinutes: ep.runtime,
                        context: modelContext
                    )
                }
                pulledCount += 1
            }
        }

        return pulledCount
    }

    /// Fetch + apply (used by the selective sync, which opts into the cloud copy).
    private func pullEpisodes(syncKey: String, since: String? = nil) async throws -> Int {
        let remote = try await fetchRemoteEpisodes(syncKey: syncKey, since: since)
        return try await applyRemoteEpisodes(remote, force: true)
    }

    // MARK: - Collections Push / Pull

    private struct RemoteCollection: Codable {
        var user_id: String
        var collection_id: String
        var name: String
        var system_image: String
        var notes: String?
        var is_pinned: Bool
        var is_smart: Bool
        var smart_rules: String?
        var completed_item_ids: [String]
        var is_deleted: Bool
        var updated_at: String?

        enum CodingKeys: String, CodingKey {
            case user_id, collection_id, name, system_image, notes, is_pinned, is_smart, smart_rules, completed_item_ids, is_deleted, updated_at
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            // Every key is encoded explicitly, including nulls. The synthesized encoder uses
            // encodeIfPresent for optionals, so a batch mixing rows with and without `notes`
            // sent inconsistent objects and PostgREST rejected it with PGRST102
            // ("All object keys must match"). RemoteMediaItem/RemoteEpisode do the same.
            try container.encode(user_id, forKey: .user_id)
            try container.encode(collection_id, forKey: .collection_id)
            try container.encode(name, forKey: .name)
            try container.encode(system_image, forKey: .system_image)
            try container.encode(notes, forKey: .notes)
            try container.encode(is_pinned, forKey: .is_pinned)
            try container.encode(is_smart, forKey: .is_smart)
            try container.encode(smart_rules, forKey: .smart_rules)
            try container.encode(completed_item_ids, forKey: .completed_item_ids)
            try container.encode(is_deleted, forKey: .is_deleted)
            try container.encode(updated_at, forKey: .updated_at)
        }
    }

    private struct RemoteCollectionItem: Codable {
        var user_id: String
        var collection_id: String
        var media_id: String
        var is_deleted: Bool
        var updated_at: String?

        enum CodingKeys: String, CodingKey {
            case user_id, collection_id, media_id, is_deleted, updated_at
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(user_id, forKey: .user_id)
            try container.encode(collection_id, forKey: .collection_id)
            try container.encode(media_id, forKey: .media_id)
            try container.encode(is_deleted, forKey: .is_deleted)
            try container.encode(updated_at, forKey: .updated_at)
        }
    }

    private func fetchRemoteCollections(syncKey: String, since: String? = nil) async throws -> [RemoteCollection] {
        let rows: [RemoteCollection] = try await fetchAllPages(
            endpoint: "user_collections",
            query: "user_id=eq.\(syncKey)&select=*",
            syncKey: syncKey,
            since: since
        )
        noteWatermark(rows.compactMap { $0.updated_at }.max())
        return rows
    }

    private func fetchRemoteCollectionItems(syncKey: String, since: String? = nil) async throws -> [RemoteCollectionItem] {
        let rows: [RemoteCollectionItem] = try await fetchAllPages(
            endpoint: "user_collection_items",
            query: "user_id=eq.\(syncKey)&select=*",
            syncKey: syncKey,
            since: since
        )
        noteWatermark(rows.compactMap { $0.updated_at }.max())
        return rows
    }

    private func pushCollections(syncKey: String, remoteById: [String: RemoteCollection]) async throws -> Int {
        let local = try modelContext.fetch(FetchDescriptor<MediaCollection>())
        let dirty = local.filter { collection in
            guard let remote = remoteById[collection.id.uuidString] else { return true }
            let remoteTime = parseISO8601(remote.updated_at) ?? .distantPast
            return (collection.updatedAt ?? .distantPast) > remoteTime
        }
        guard !dirty.isEmpty else { return 0 }

        let chunkSize = 100
        var pushedCount = 0
        for chunk in stride(from: 0, to: dirty.count, by: chunkSize) {
            let slice = Array(dirty[chunk..<min(chunk + chunkSize, dirty.count)])
            let payloads = slice.map { collection in
                RemoteCollection(
                    user_id: syncKey,
                    collection_id: collection.id.uuidString,
                    name: collection.name,
                    system_image: collection.systemImage,
                    notes: collection.notes,
                    is_pinned: collection.isPinned,
                    is_smart: collection.isSmart,
                    smart_rules: collection.smartRulesData.flatMap { String(data: $0, encoding: .utf8) },
                    completed_item_ids: collection.completedItemIDs,
                    is_deleted: false,
                    updated_at: iso8601Formatter.string(from: Date())
                )
            }
            try await postRemote(endpoint: "user_collections", syncKey: syncKey, body: payloads)
            pushedCount += slice.count
        }
        return pushedCount
    }

    /// Posts a tombstone for a collection so its deletion propagates to other devices.
    ///
    /// macOS removes collection rows outright, so there is no local row left to push a
    /// tombstone for — the delete path must call this *before* deleting. Takes primitives
    /// rather than the `@Model` so it can be called from a detached `Task`.
    func markCollectionDeleted(
        id: UUID,
        name: String,
        systemImage: String,
        notes: String?,
        isPinned: Bool,
        isSmart: Bool,
        smartRules: String?,
        completedItemIDs: [String]
    ) async {
        let syncKey = Self.getOrGenerateSyncKey()
        guard !Self.supabaseURL.isEmpty, !Self.supabaseAnonKey.isEmpty, !syncKey.isEmpty else { return }
        let payload = RemoteCollection(
            user_id: syncKey,
            collection_id: id.uuidString,
            name: name,
            system_image: systemImage,
            notes: notes,
            is_pinned: isPinned,
            is_smart: isSmart,
            smart_rules: smartRules,
            completed_item_ids: completedItemIDs,
            is_deleted: true,
            updated_at: iso8601Formatter.string(from: Date())
        )
        do {
            try await postRemote(endpoint: "user_collections", syncKey: syncKey, body: [payload])
        } catch {
            AppLogger.error("markCollectionDeleted failed: \(error.localizedDescription)", logger: AppLogger.sync)
        }
    }

    private func applyRemoteCollections(_ remote: [RemoteCollection], force: Bool = false) async throws -> Int {
        guard !remote.isEmpty else { return 0 }
        var pulledCount = 0
        for item in remote {
            guard let uuid = UUID(uuidString: item.collection_id) else { continue }
            let descriptor = FetchDescriptor<MediaCollection>(predicate: #Predicate { $0.id == uuid })
            let existing = try? modelContext.fetch(descriptor).first
            let remoteTime = parseISO8601(item.updated_at) ?? .distantPast

            if let existing {
                if item.is_deleted {
                    if force || remoteTime > (existing.updatedAt ?? .distantPast) {
                        modelContext.delete(existing)
                        pulledCount += 1
                    }
                    continue
                }
                let localRules = existing.smartRulesData.flatMap { String(data: $0, encoding: .utf8) }
                let differs = existing.name != item.name
                    || existing.systemImage != item.system_image
                    || (existing.notes ?? "") != (item.notes ?? "")
                    || existing.isPinned != item.is_pinned
                    || existing.completedItemIDs != item.completed_item_ids
                    || localRules != item.smart_rules
                guard differs else { continue }
                guard force || remoteTime > (existing.updatedAt ?? .distantPast) else { continue }
                existing.name = item.name
                existing.systemImage = item.system_image
                existing.notes = item.notes
                existing.isPinned = item.is_pinned
                existing.completedItemIDs = item.completed_item_ids
                existing.smartRulesData = item.smart_rules.flatMap { $0.data(using: .utf8) }
                existing.updatedAt = remoteTime
                pulledCount += 1
            } else if !item.is_deleted {
                let created = MediaCollection(id: uuid, name: item.name, systemImage: item.system_image, isSmart: item.is_smart)
                created.notes = item.notes
                created.isPinned = item.is_pinned
                created.completedItemIDs = item.completed_item_ids
                created.smartRulesData = item.smart_rules.flatMap { $0.data(using: .utf8) }
                created.updatedAt = remoteTime
                modelContext.insert(created)
                pulledCount += 1
            }
        }
        return pulledCount
    }

    /// Reconciles collection membership (the join table): upserts the local set, tombstones
    /// rows removed locally, and returns the number of rows pushed.
    private func pushCollectionItems(syncKey: String, remote: [RemoteCollectionItem]) async throws -> Int {
        let collections = try modelContext.fetch(FetchDescriptor<MediaCollection>())
        var desired: [String: Set<String>] = [:]
        for collection in collections where !collection.isSmart {
            desired[collection.id.uuidString] = Set(collection.items.map { $0.id })
        }

        let now = iso8601Formatter.string(from: Date())
        let remoteByKey = Dictionary(
            remote.map { ("\($0.collection_id)|\($0.media_id)", $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var payloads: [RemoteCollectionItem] = []
        for (collectionID, mediaIDs) in desired {
            for mediaID in mediaIDs where remoteByKey["\(collectionID)|\(mediaID)"]?.is_deleted != false {
                payloads.append(RemoteCollectionItem(user_id: syncKey, collection_id: collectionID, media_id: mediaID, is_deleted: false, updated_at: now))
            }
        }
        // Tombstone rows that are still in the cloud but no longer local — but only while the
        // collection itself still exists (a whole-collection delete is handled above).
        for row in remote where !row.is_deleted {
            guard desired.keys.contains(row.collection_id) else { continue }
            if desired[row.collection_id]?.contains(row.media_id) != true {
                payloads.append(RemoteCollectionItem(user_id: syncKey, collection_id: row.collection_id, media_id: row.media_id, is_deleted: true, updated_at: now))
            }
        }

        guard !payloads.isEmpty else { return 0 }
        let chunkSize = 200
        var pushedCount = 0
        for chunk in stride(from: 0, to: payloads.count, by: chunkSize) {
            let slice = Array(payloads[chunk..<min(chunk + chunkSize, payloads.count)])
            try await postRemote(endpoint: "user_collection_items", syncKey: syncKey, body: slice)
            pushedCount += slice.count
        }
        return pushedCount
    }

    private func applyRemoteCollectionItems(_ remote: [RemoteCollectionItem]) async throws -> Int {
        guard !remote.isEmpty else { return 0 }
        let collections = try modelContext.fetch(FetchDescriptor<MediaCollection>())
        let byID = Dictionary(collections.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })

        var mediaCache: [String: MediaItem] = [:]
        var pulledCount = 0
        for row in remote {
            guard let collection = byID[row.collection_id] else { continue }
            let has = collection.items.contains { $0.id == row.media_id }
            if row.is_deleted {
                if has {
                    collection.items.removeAll { $0.id == row.media_id }
                    collection.completedItemIDs.removeAll { $0 == row.media_id }
                    pulledCount += 1
                }
            } else if !has {
                let media: MediaItem?
                if let cached = mediaCache[row.media_id] {
                    media = cached
                } else {
                    let id = row.media_id
                    let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == id })
                    media = try? modelContext.fetch(descriptor).first
                    if let media { mediaCache[row.media_id] = media }
                }
                if let media {
                    collection.items.append(media)
                    pulledCount += 1
                }
            }
        }
        return pulledCount
    }

    // MARK: - Watch History (cycles + events)

    /// Id-only projection, so the impact preview can count what the cloud is missing without
    /// downloading every row.
    private struct RemoteID: Codable {
        var cycle_id: String?
        var event_id: String?
    }

    private struct RemoteWatchCycle: Codable {
        var user_id: String
        var cycle_id: String
        var media_id: String
        var kind: String
        var started_at: String
        var completed_at: String?
        var state: String
        var is_rewatch: Bool
        var is_complete: Bool
        var scope_episode_ids: [String]
        var is_backfilled: Bool
        var updated_at: String?

        enum CodingKeys: String, CodingKey {
            case user_id, cycle_id, media_id, kind, started_at, completed_at, state
            case is_rewatch, is_complete, scope_episode_ids, is_backfilled, updated_at
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            // Every key explicit, including nulls: the synthesized encoder omits nil
            // optionals, and PostgREST rejects a batch with differing keys (PGRST102).
            try container.encode(user_id, forKey: .user_id)
            try container.encode(cycle_id, forKey: .cycle_id)
            try container.encode(media_id, forKey: .media_id)
            try container.encode(kind, forKey: .kind)
            try container.encode(started_at, forKey: .started_at)
            try container.encode(completed_at, forKey: .completed_at)
            try container.encode(state, forKey: .state)
            try container.encode(is_rewatch, forKey: .is_rewatch)
            try container.encode(is_complete, forKey: .is_complete)
            try container.encode(scope_episode_ids, forKey: .scope_episode_ids)
            try container.encode(is_backfilled, forKey: .is_backfilled)
            try container.encode(updated_at, forKey: .updated_at)
        }
    }

    private struct RemoteWatchEvent: Codable {
        var user_id: String
        var event_id: String
        var cycle_id: String
        var media_id: String
        var episode_id: String?
        var watched_at: String
        var source: String
        var timezone_identifier: String?
        var runtime_minutes: Int?
        var voided_at: String?
        var deduplication_key: String
        var is_backfilled: Bool
        var updated_at: String?

        enum CodingKeys: String, CodingKey {
            case user_id, event_id, cycle_id, media_id, episode_id, watched_at, source
            case timezone_identifier, runtime_minutes, voided_at, deduplication_key
            case is_backfilled, updated_at
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(user_id, forKey: .user_id)
            try container.encode(event_id, forKey: .event_id)
            try container.encode(cycle_id, forKey: .cycle_id)
            try container.encode(media_id, forKey: .media_id)
            try container.encode(episode_id, forKey: .episode_id)
            try container.encode(watched_at, forKey: .watched_at)
            try container.encode(source, forKey: .source)
            try container.encode(timezone_identifier, forKey: .timezone_identifier)
            try container.encode(runtime_minutes, forKey: .runtime_minutes)
            try container.encode(voided_at, forKey: .voided_at)
            try container.encode(deduplication_key, forKey: .deduplication_key)
            try container.encode(is_backfilled, forKey: .is_backfilled)
            try container.encode(updated_at, forKey: .updated_at)
        }
    }

    private func fetchRemoteWatchCycles(syncKey: String, since: String? = nil) async throws -> [RemoteWatchCycle] {
        let rows: [RemoteWatchCycle] = try await fetchAllPages(
            endpoint: "user_watch_cycles",
            query: "user_id=eq.\(syncKey)&select=*",
            syncKey: syncKey,
            since: since
        )
        noteWatermark(rows.compactMap { $0.updated_at }.max())
        return rows
    }

    private func fetchRemoteWatchEvents(syncKey: String, since: String? = nil) async throws -> [RemoteWatchEvent] {
        let rows: [RemoteWatchEvent] = try await fetchAllPages(
            endpoint: "user_watch_events",
            query: "user_id=eq.\(syncKey)&select=*",
            syncKey: syncKey,
            since: since
        )
        noteWatermark(rows.compactMap { $0.updated_at }.max())
        return rows
    }

    /// True when [stamp] is newer than the incremental watermark — or when there is no
    /// watermark, i.e. the last sync was a full pull, where "absent remotely" really does mean
    /// "missing from the cloud".
    private func changedSince(_ stamp: Date?, _ watermark: String?) -> Bool {
        guard let stamp else { return false }
        guard let watermark, let since = parseISO8601(watermark) else { return true }
        return stamp > since
    }

    /// A cycle's "last meaningful change". `WatchCycle` has no modified timestamp of its own,
    /// but it only ever moves forward (started → completed), so `completedAt ?? startedAt`
    /// tracks it well enough to order pushes.
    private func cycleChangeTime(startedAt: Date, completedAt: Date?) -> Date {
        completedAt ?? startedAt
    }

    private func pushWatchCycles(syncKey: String, remoteById: [String: RemoteWatchCycle], watermark: String? = nil) async throws -> Int {
        let local = try modelContext.fetch(FetchDescriptor<WatchCycle>())
        let dirty = local.filter { cycle in
            // A watermarked fetch omits unchanged rows, so "absent" means "unchanged", not
            // "never pushed" — only send one this device actually moved since the last sync.
            guard let remote = remoteById[cycle.id.uuidString] else {
                return changedSince(cycle.startedAt, watermark) || changedSince(cycle.completedAt, watermark)
            }
            let remoteTime = cycleChangeTime(
                startedAt: parseISO8601(remote.started_at) ?? .distantPast,
                completedAt: parseISO8601(remote.completed_at)
            )
            return cycleChangeTime(startedAt: cycle.startedAt, completedAt: cycle.completedAt) > remoteTime
        }
        guard !dirty.isEmpty else { return 0 }

        let chunkSize = 100
        var pushedCount = 0
        for chunk in stride(from: 0, to: dirty.count, by: chunkSize) {
            let slice = Array(dirty[chunk..<min(chunk + chunkSize, dirty.count)])
            let payloads = slice.map { cycle in
                RemoteWatchCycle(
                    user_id: syncKey,
                    cycle_id: cycle.id.uuidString,
                    media_id: cycle.mediaID,
                    kind: cycle.kindRaw,
                    started_at: iso8601Formatter.string(from: cycle.startedAt),
                    completed_at: cycle.completedAt.map { iso8601Formatter.string(from: $0) },
                    state: cycle.stateRaw,
                    is_rewatch: cycle.isRewatch,
                    is_complete: cycle.isComplete,
                    scope_episode_ids: cycle.scopeEpisodeIDs,
                    is_backfilled: cycle.isBackfilled,
                    updated_at: iso8601Formatter.string(from: Date())
                )
            }
            try await postRemote(endpoint: "user_watch_cycles", syncKey: syncKey, body: payloads)
            pushedCount += slice.count
        }
        return pushedCount
    }

    private func pushWatchEvents(syncKey: String, remoteById: [String: RemoteWatchEvent], watermark: String? = nil) async throws -> Int {
        let local = try modelContext.fetch(FetchDescriptor<WatchEvent>())
        let dirty = local.filter { event in
            // Same watermark subtlety as cycles.
            guard let remote = remoteById[event.id.uuidString] else {
                return changedSince(event.watchedAt, watermark) || changedSince(event.voidedAt, watermark)
            }
            // Events are immutable facts; the only forward change is a void.
            return event.voidedAt != nil && remote.voided_at == nil
        }
        guard !dirty.isEmpty else { return 0 }

        let chunkSize = 100
        var pushedCount = 0
        for chunk in stride(from: 0, to: dirty.count, by: chunkSize) {
            let slice = Array(dirty[chunk..<min(chunk + chunkSize, dirty.count)])
            let payloads = slice.map { event in
                RemoteWatchEvent(
                    user_id: syncKey,
                    event_id: event.id.uuidString,
                    cycle_id: event.cycleID.uuidString,
                    media_id: event.mediaID,
                    episode_id: event.episodeID,
                    watched_at: iso8601Formatter.string(from: event.watchedAt),
                    source: event.sourceRaw,
                    timezone_identifier: event.timezoneIdentifier,
                    runtime_minutes: event.runtimeMinutes,
                    voided_at: event.voidedAt.map { iso8601Formatter.string(from: $0) },
                    deduplication_key: event.deduplicationKey,
                    is_backfilled: event.isBackfilled,
                    updated_at: iso8601Formatter.string(from: Date())
                )
            }
            try await postRemote(endpoint: "user_watch_events", syncKey: syncKey, body: payloads)
            pushedCount += slice.count
        }
        return pushedCount
    }

    private func applyRemoteWatchCycles(_ remote: [RemoteWatchCycle]) async throws -> Int {
        guard !remote.isEmpty else { return 0 }
        var pulledCount = 0
        for item in remote {
            guard let uuid = UUID(uuidString: item.cycle_id) else { continue }
            let descriptor = FetchDescriptor<WatchCycle>(predicate: #Predicate { $0.id == uuid })
            let remoteCompleted = parseISO8601(item.completed_at)
            if let existing = try? modelContext.fetch(descriptor).first {
                // Only completion moves; started/isRewatch/scope are fixed at creation.
                let remoteTime = cycleChangeTime(
                    startedAt: parseISO8601(item.started_at) ?? .distantPast,
                    completedAt: remoteCompleted
                )
                guard remoteTime > cycleChangeTime(startedAt: existing.startedAt, completedAt: existing.completedAt) else { continue }
                existing.stateRaw = item.state
                existing.completedAt = remoteCompleted
                existing.isComplete = item.is_complete
                pulledCount += 1
            } else {
                let created = WatchCycle(
                    id: uuid,
                    mediaID: item.media_id,
                    kind: WatchCycleKind(rawValue: item.kind) ?? .movie,
                    startedAt: parseISO8601(item.started_at) ?? Date(),
                    completedAt: remoteCompleted,
                    state: WatchCycleState(rawValue: item.state) ?? .active,
                    isBackfilled: true,
                    isRewatch: item.is_rewatch,
                    isComplete: item.is_complete,
                    scopeEpisodeIDs: item.scope_episode_ids
                )
                modelContext.insert(created)
                pulledCount += 1
            }
        }
        return pulledCount
    }

    private func applyRemoteWatchEvents(_ remote: [RemoteWatchEvent]) async throws -> Int {
        guard !remote.isEmpty else { return 0 }
        var pulledCount = 0
        for item in remote {
            guard let uuid = UUID(uuidString: item.event_id) else { continue }
            let descriptor = FetchDescriptor<WatchEvent>(predicate: #Predicate { $0.id == uuid })
            let remoteVoided = parseISO8601(item.voided_at)

            if let existing = try? modelContext.fetch(descriptor).first {
                if existing.voidedAt == nil, remoteVoided != nil {
                    existing.voidedAt = remoteVoided
                    pulledCount += 1
                }
                continue
            }
            let watchedAt = parseISO8601(item.watched_at) ?? Date()
            // The media/episode pull synthesises an event when a watch arrives without history
            // (so the story reads continuously), and its dedup key differs from the origin
            // device's — without this check the same watch would be logged twice.
            if hasEquivalentEvent(mediaID: item.media_id, episodeID: item.episode_id, watchedAt: watchedAt) { continue }

            let created = WatchEvent(
                id: uuid,
                cycleID: UUID(uuidString: item.cycle_id) ?? UUID(),
                mediaID: item.media_id,
                episodeID: item.episode_id,
                watchedAt: watchedAt,
                source: WatchEventSource(rawValue: item.source) ?? .imported,
                timezoneIdentifier: item.timezone_identifier,
                runtimeMinutes: item.runtime_minutes,
                voidedAt: remoteVoided,
                deduplicationKey: item.deduplication_key,
                isBackfilled: true
            )
            modelContext.insert(created)
            pulledCount += 1
        }
        return pulledCount
    }

    /// True when a local event already covers the same watch on the same day.
    private func hasEquivalentEvent(mediaID: String, episodeID: String?, watchedAt: Date) -> Bool {
        let descriptor = FetchDescriptor<WatchEvent>(
            predicate: #Predicate { $0.mediaID == mediaID && $0.voidedAt == nil }
        )
        guard let candidates = try? modelContext.fetch(descriptor) else { return false }
        let calendar = Calendar.current
        return candidates.contains { candidate in
            candidate.episodeID == episodeID && calendar.isDate(candidate.watchedAt, inSameDayAs: watchedAt)
        }
    }

    // MARK: - PostgREST Networking Helpers

    private func postRemote<T: Encodable>(endpoint: String, syncKey: String, body: T) async throws {
        guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/\(endpoint)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Self.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(syncKey, forHTTPHeaderField: "x-sync-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Upsert mode: merge duplicates on primary key conflict
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown response"
            AppLogger.error("Supabase \(endpoint) returned HTTP \(http.statusCode): \(errorBody)", logger: AppLogger.sync)
            // Carry the body: PostgREST names the offending column/constraint, which is the
            // difference between a useful toast and a bare "400".
            throw APIError.requestFailedWithBody(http.statusCode, errorBody)
        }
    }

    private func sendRequest(url: URL, syncKey: String, method: String, range: String? = nil) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Self.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(syncKey, forHTTPHeaderField: "x-sync-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        return try await URLSession.shared.data(for: request)
    }

    /// GETs every page of a PostgREST endpoint.
    ///
    /// PostgREST caps an unpaginated response at 1000 rows, so a single GET silently
    /// truncated a library past that size — rows beyond the first page never synced.
    /// Newest server `updated_at` seen during this service's pulls, used to advance the
    /// incremental watermark. Server time, not the device clock.
    private var observedMaxUpdatedAt: String?

    private func noteWatermark(_ stamp: String?) {
        guard let stamp, !stamp.isEmpty else { return }
        if observedMaxUpdatedAt.map({ stamp > $0 }) ?? true { observedMaxUpdatedAt = stamp }
    }

    /// The watermark to persist: the newest stamp seen, backed off slightly so a read racing an
    /// in-flight commit can't skip that row on the next pull.
    var newWatermark: String? {
        guard let newest = observedMaxUpdatedAt else { return nil }
        guard let date = parseISO8601(newest) else { return newest }
        return iso8601Formatter.string(from: date.addingTimeInterval(-5))
    }

    private func fetchAllPages<T: Decodable>(
        endpoint: String,
        query: String,
        syncKey: String,
        since: String? = nil
    ) async throws -> [T] {
        // Incremental watermark: every table carries a server-set updated_at, so an unchanged
        // table comes back empty instead of re-downloading the whole library.
        var fullQuery = query
        if let since, !since.isEmpty {
            // `+` in the offset (…+00:00) is legal in a query string but decodes as a space,
            // which silently breaks the filter — so encode it.
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "+")
            if let encoded = "gt.\(since)".addingPercentEncoding(withAllowedCharacters: allowed) {
                fullQuery += "&updated_at=\(encoded)"
            }
        }
        var out: [T] = []
        var offset = 0
        let pageSize = 1000
        while true {
            guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/\(endpoint)?\(fullQuery)") else { break }
            let (data, response) = try await sendRequest(
                url: url,
                syncKey: syncKey,
                method: "GET",
                range: "\(offset)-\(offset + pageSize - 1)"
            )
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { break }
            let page = (try? JSONDecoder().decode([T].self, from: data)) ?? []
            if page.isEmpty { break }
            out.append(contentsOf: page)
            offset += page.count
            if page.count < pageSize { break }
        }
        return out
    }

    /// `media_id` → `date_added` for every cloud row, so a sync can tell which local titles
    /// still need their added date backfilled.
    private struct RemoteMediaDateAdded: Codable {
        var media_id: String
        var date_added: String?
    }

    private func fetchRemoteDateAdded(syncKey: String, since: String? = nil) async throws -> [String: String] {
        let rows: [RemoteMediaDateAdded] = try await fetchAllPages(
            endpoint: "user_media",
            query: "user_id=eq.\(syncKey)&select=media_id,date_added",
            syncKey: syncKey,
            since: since
        )
        // Deliberately no watermark from this projection: it selects `date_added`, which is an
        // arbitrary past instant, not the row's server write time.
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            row.date_added.map { (row.media_id, $0) }
        })
    }

    private func fetchRemoteMedia(syncKey: String, since: String? = nil) async throws -> [RemoteMediaItem] {
        let rows: [RemoteMediaItem] = try await fetchAllPages(
            endpoint: "user_media",
            query: "user_id=eq.\(syncKey)&select=*",
            syncKey: syncKey,
            since: since
        )
        noteWatermark(rows.compactMap { $0.updated_at }.max())
        return rows
    }

    private func fetchRemoteEpisodes(syncKey: String, since: String? = nil) async throws -> [RemoteEpisode] {
        let rows: [RemoteEpisode] = try await fetchAllPages(
            endpoint: "user_episodes",
            query: "user_id=eq.\(syncKey)&select=*",
            syncKey: syncKey,
            since: since
        )
        noteWatermark(rows.compactMap { $0.updated_at }.max())
        return rows
    }
}

/// The instant a local row was last *edited by the user*, used to resolve sync conflicts
/// (last-writer-wins). Mirrors Android's `lastInteractionDate` comparison.
///
/// `lastUpdated` is deliberately excluded: it's the metadata/cache-refresh stamp, so a
/// background refresh would otherwise make the row look freshly edited and win every
/// conflict against a genuine change made on the other device.
private extension MediaItem {
    var syncEditTime: Date {
        lastInteractionDate ?? lastStateChangeDate ?? .distantPast
    }
}

private extension TVEpisode {
    var syncEditTime: Date {
        watchedDate ?? lastWatchedDate ?? .distantPast
    }
}
