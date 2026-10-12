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
            // 1. Fetch remote media
            let urlString = "\(Self.supabaseURL)/rest/v1/user_media?user_id=eq.\(syncKey)&select=*"
            if let url = URL(string: urlString) {
                let (data, response) = try await sendRequest(url: url, syncKey: syncKey, method: "GET")
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    let remoteItems = (try? JSONDecoder().decode([RemoteMediaItem].self, from: data)) ?? []
                    let remoteMap = Dictionary(uniqueKeysWithValues: remoteItems.map { ($0.media_id, $0) })

                    var descriptor = FetchDescriptor<MediaItem>()
                    descriptor.propertiesToFetch = [\.id, \.title, \.typeValue, \.stateValue, \.tasteValue, \.posterURL, \.customPosterURL, \.lastUpdated, \.lastStateChangeDate, \.lastInteractionDate]
                    let localItems = (try? modelContext.fetch(descriptor)) ?? []
                    let localMap = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id, $0) })

                    for remote in remoteItems {
                        if let local = localMap[remote.media_id] {
                            if local.stateValue != remote.state || local.tasteValue != remote.taste {
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
                        } else {
                            let itemDate = local.lastUpdated ?? local.lastStateChangeDate ?? local.lastInteractionDate ?? Date.distantPast
                            if itemDate.timeIntervalSince1970 > lastSyncTimestamp {
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
                    }
                }
            }

            // 2. Fetch remote episodes count
            let epUrlString = "\(Self.supabaseURL)/rest/v1/user_episodes?user_id=eq.\(syncKey)&select=episode_id,is_watched"
            if let epUrl = URL(string: epUrlString) {
                let (epData, epResponse) = try await sendRequest(url: epUrl, syncKey: syncKey, method: "GET")
                if let http = epResponse as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    let remoteEps = (try? JSONDecoder().decode([RemoteEpisode].self, from: epData)) ?? []
                    let remoteEpMap = Dictionary(uniqueKeysWithValues: remoteEps.map { ($0.episode_id, $0.is_watched) })

                    var epDescriptor = FetchDescriptor<TVEpisode>()
                    epDescriptor.propertiesToFetch = [\.uniqueID, \.isWatched, \.showID, \.seasonNumber, \.episodeNumber]
                    let localEpisodes = (try? modelContext.fetch(epDescriptor)) ?? []

                    var mediaDescriptor = FetchDescriptor<MediaItem>()
                    mediaDescriptor.propertiesToFetch = [\.id, \.title, \.posterURL, \.customPosterURL]
                    let allMedia = (try? modelContext.fetch(mediaDescriptor)) ?? []
                    let mediaByNumericID: [Int: MediaItem] = Dictionary(
                        uniqueKeysWithValues: allMedia.compactMap { item in
                            guard let num = Int(item.id.split(separator: "_").last ?? "") else { return nil }
                            return (num, item)
                        }
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
                }
            }
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
                summary.mediaPulled = try await pullMediaItems(syncKey: syncKey, since: lastSyncTimestamp, filterIDs: allowedPullIDs)
            }

            // 3. Episodes sync
            if syncEpisodes {
                summary.episodesPushed = try await pushEpisodes(syncKey: syncKey, since: lastSyncTimestamp)
                summary.episodesPulled = try await pullEpisodes(syncKey: syncKey, since: lastSyncTimestamp)
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
        let lastSyncTimestamp = UserDefaults.standard.double(forKey: UserDefaultsKeys.cloudSyncLastTimestamp.rawValue)
        let now = Date().timeIntervalSince1970

        do {
            // 1. Push Media Items changed since last sync
            summary.mediaPushed = try await pushMediaItems(syncKey: syncKey, since: lastSyncTimestamp)

            // 2. Pull Remote Media Items changed since last sync
            summary.mediaPulled = try await pullMediaItems(syncKey: syncKey, since: lastSyncTimestamp)

            // 3. Push TV Episodes changed since last sync
            summary.episodesPushed = try await pushEpisodes(syncKey: syncKey, since: lastSyncTimestamp)

            // 4. Pull Remote TV Episodes changed since last sync
            summary.episodesPulled = try await pullEpisodes(syncKey: syncKey, since: lastSyncTimestamp)

            // Update timestamp on successful sync
            UserDefaults.standard.set(now, forKey: UserDefaultsKeys.cloudSyncLastTimestamp.rawValue)
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

    private func pushMediaItems(syncKey: String, since: TimeInterval) async throws -> Int {
        var descriptor = FetchDescriptor<MediaItem>()
        descriptor.propertiesToFetch = [
            \.id, \.typeValue, \.stateValue, \.tasteValue, \.customPosterURL,
            \.isSoftDeleted, \.lastInteractionDate, \.lastStateChangeDate, \.lastUpdated
        ]

        let localItems = try modelContext.fetch(descriptor)
        let dirtyItems = localItems.filter { item in
            if since == 0 { return true }
            let itemDate = item.lastUpdated ?? item.lastStateChangeDate ?? item.lastInteractionDate ?? Date.distantPast
            return itemDate.timeIntervalSince1970 > since
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

    private func pullMediaItems(syncKey: String, since: TimeInterval, filterIDs: Set<String>? = nil) async throws -> Int {
        var urlString = "\(Self.supabaseURL)/rest/v1/user_media?user_id=eq.\(syncKey)&select=*"
        if since > 0 {
            let sinceDate = Date(timeIntervalSince1970: since)
            let formatted = iso8601Formatter.string(from: sinceDate)
            if let encoded = formatted.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString += "&updated_at=gt.\(encoded)"
            }
        }

        guard let url = URL(string: urlString) else { return 0 }
        let (data, response) = try await sendRequest(url: url, syncKey: syncKey, method: "GET")
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return 0
        }

        let rawRemoteItems = try JSONDecoder().decode([RemoteMediaItem].self, from: data)
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
                // Update existing item if remote state is newer
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

    private func pushEpisodes(syncKey: String, since: TimeInterval) async throws -> Int {
        let descriptor = FetchDescriptor<TVEpisode>()
        let episodes = try modelContext.fetch(descriptor)

        let dirtyEpisodes = episodes.filter { ep in
            if since == 0 { return ep.isWatched }
            let watchDate = ep.watchedDate ?? ep.lastWatchedDate ?? Date.distantPast
            return watchDate.timeIntervalSince1970 > since
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

    private func pullEpisodes(syncKey: String, since: TimeInterval) async throws -> Int {
        var urlString = "\(Self.supabaseURL)/rest/v1/user_episodes?user_id=eq.\(syncKey)&select=*"
        if since > 0 {
            let sinceDate = Date(timeIntervalSince1970: since)
            let formatted = iso8601Formatter.string(from: sinceDate)
            if let encoded = formatted.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString += "&updated_at=gt.\(encoded)"
            }
        }

        guard let url = URL(string: urlString) else { return 0 }
        let (data, response) = try await sendRequest(url: url, syncKey: syncKey, method: "GET")
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            return 0
        }

        let remoteEpisodes = try JSONDecoder().decode([RemoteEpisode].self, from: data)
        guard !remoteEpisodes.isEmpty else { return 0 }

        var pulledCount = 0
        for remote in remoteEpisodes {
            let epID = remote.episode_id
            let descriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.uniqueID == epID })
            if let ep = try? modelContext.fetch(descriptor).first {
                if ep.isWatched != remote.is_watched {
                    ep.isWatched = remote.is_watched
                    if let dateStr = remote.watched_date {
                        ep.watchedDate = parseISO8601(dateStr)
                        ep.lastWatchedDate = ep.watchedDate
                    }
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

    private func sendRequest(url: URL, syncKey: String, method: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(Self.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Self.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(syncKey, forHTTPHeaderField: "x-sync-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await URLSession.shared.data(for: request)
    }
}
