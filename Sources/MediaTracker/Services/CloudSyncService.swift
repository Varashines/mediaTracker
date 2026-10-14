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
        var errorDescription: String? = nil

        var totalChanges: Int {
            titlesToImport.count + titlesToUpdate.count + titlesToUpload.count + totalEpisodesToImport + totalEpisodesToUpload
        }

        var hasChanges: BooleanLiteralType {
            totalChanges > 0
        }
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

        do {
            // 1. Fetch remote media (paginated: a single GET truncates at 1000 rows)
            let remoteItems = try await fetchRemoteMedia(syncKey: syncKey)
            let remoteMap = Dictionary(remoteItems.map { ($0.media_id, $0) }, uniquingKeysWith: { first, _ in first })

            var descriptor = FetchDescriptor<MediaItem>()
            descriptor.propertiesToFetch = [\.id, \.title, \.typeValue, \.stateValue, \.tasteValue, \.posterURL, \.customPosterURL, \.isSoftDeleted, \.lastUpdated, \.lastStateChangeDate, \.lastInteractionDate]
            let localItems = (try? modelContext.fetch(descriptor)) ?? []
            let localMap = Dictionary(localItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            for remote in remoteItems {
                if let local = localMap[remote.media_id] {
                    // A differing state/taste *or* a differing soft-delete is a conflict.
                    let differs = local.stateValue != remote.state
                        || local.tasteValue != remote.taste
                        || local.isSoftDeleted != remote.is_soft_deleted
                    if differs {
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
                } else if local.syncEditTime.timeIntervalSince1970 > lastSyncTimestamp {
                    if !impact.titlesToUpdate.contains(where: { $0.id == local.id }) {
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
            }

            // 2. Fetch remote episodes (paginated: a single GET truncates at 1000 rows)
            let remoteEps = try await fetchRemoteEpisodes(syncKey: syncKey)
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
        let now = Date().timeIntervalSince1970

        do {
            // 1. Push approved local titles
            let descriptor = FetchDescriptor<MediaItem>()
            let localItems = try modelContext.fetch(descriptor)
            let itemsToUpload = localItems.filter { approvedUploadIDs.contains($0.id) }
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
                summary.mediaPulled = try await pullMediaItems(syncKey: syncKey, filterIDs: allowedPullIDs)
            }

            // 3. Episodes sync
            if syncEpisodes {
                summary.episodesPushed = try await pushEpisodes(syncKey: syncKey, since: lastSyncTimestamp)
                summary.episodesPulled = try await pullEpisodes(syncKey: syncKey)
            }

            UserDefaults.standard.set(now, forKey: UserDefaultsKeys.cloudSyncLastTimestamp.rawValue)
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
        var updated_at: String?

        enum CodingKeys: String, CodingKey {
            case user_id, media_id, type, state, taste, custom_poster_url, is_soft_deleted, last_interaction_date, last_state_change_date, updated_at
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
                existing.syncCachedProperties(dirty: .progress)
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
    private func pullMediaItems(syncKey: String, filterIDs: Set<String>? = nil) async throws -> Int {
        let remote = try await fetchRemoteMedia(syncKey: syncKey)
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
                pulledCount += 1
            }
        }

        return pulledCount
    }

    /// Fetch + apply (used by the selective sync, which opts into the cloud copy).
    private func pullEpisodes(syncKey: String) async throws -> Int {
        let remote = try await fetchRemoteEpisodes(syncKey: syncKey)
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
    }

    private struct RemoteCollectionItem: Codable {
        var user_id: String
        var collection_id: String
        var media_id: String
        var is_deleted: Bool
        var updated_at: String?
    }

    private func fetchRemoteCollections(syncKey: String) async throws -> [RemoteCollection] {
        try await fetchAllPages(endpoint: "user_collections", query: "user_id=eq.\(syncKey)&select=*", syncKey: syncKey)
    }

    private func fetchRemoteCollectionItems(syncKey: String) async throws -> [RemoteCollectionItem] {
        try await fetchAllPages(endpoint: "user_collection_items", query: "user_id=eq.\(syncKey)&select=*", syncKey: syncKey)
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
            throw APIError.requestFailed(http.statusCode)
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
    private func fetchAllPages<T: Decodable>(
        endpoint: String,
        query: String,
        syncKey: String
    ) async throws -> [T] {
        var out: [T] = []
        var offset = 0
        let pageSize = 1000
        while true {
            guard let url = URL(string: "\(Self.supabaseURL)/rest/v1/\(endpoint)?\(query)") else { break }
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

    private func fetchRemoteMedia(syncKey: String) async throws -> [RemoteMediaItem] {
        try await fetchAllPages(endpoint: "user_media", query: "user_id=eq.\(syncKey)&select=*", syncKey: syncKey)
    }

    private func fetchRemoteEpisodes(syncKey: String) async throws -> [RemoteEpisode] {
        try await fetchAllPages(endpoint: "user_episodes", query: "user_id=eq.\(syncKey)&select=*", syncKey: syncKey)
    }
}

/// The instant a local row was last edited, used to resolve sync conflicts
/// (last-writer-wins). Mirrors Android's `lastStateChangeDate` comparison.
private extension MediaItem {
    var syncEditTime: Date {
        lastUpdated ?? lastStateChangeDate ?? lastInteractionDate ?? .distantPast
    }
}

private extension TVEpisode {
    var syncEditTime: Date {
        watchedDate ?? lastWatchedDate ?? .distantPast
    }
}
