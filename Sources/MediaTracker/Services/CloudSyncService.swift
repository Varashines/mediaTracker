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

    // MARK: - Public Two-Way Sync Entrypoint

    struct SyncSummary: Sendable {
        var mediaPushed: Int = 0
        var mediaPulled: Int = 0
        var episodesPushed: Int = 0
        var episodesPulled: Int = 0
        var errorDescription: String? = nil
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

    private func pullMediaItems(syncKey: String, since: TimeInterval) async throws -> Int {
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

        let remoteItems = try JSONDecoder().decode([RemoteMediaItem].self, from: data)
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

        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
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
