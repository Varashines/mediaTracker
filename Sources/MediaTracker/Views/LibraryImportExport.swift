import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryBackup: Codable, Sendable {
    let items: [MediaItemData]
    var collections: [CollectionBackupData]?
    var version: Int = 1

    static func createDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let doubleValue = try? container.decode(Double.self) {
                if doubleValue > 1_000_000_000 {
                    return Date(timeIntervalSince1970: doubleValue)
                }
                return Date(timeIntervalSinceReferenceDate: doubleValue)
            }
            if let stringValue = try? container.decode(String.self) {
                let isoFormatter = ISO8601DateFormatter()
                if let date = isoFormatter.date(from: stringValue) {
                    return date
                }
                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
                if let date = df.date(from: stringValue) {
                    return date
                }
                df.dateFormat = "yyyy-MM-dd"
                if let date = df.date(from: stringValue) {
                    return date
                }
            }
            return Date()
        }
        return decoder
    }
}

struct MediaItemData: Codable, Sendable {
    let id: String
    let title: String
    let type: String
    let state: String
    let dateAdded: Date
    let taste: String?
    let watchedEpisodeIDs: [String]?
    /// Most recent interaction (watch/taste/state change) — preserved across restores.
    let lastInteractionDate: Date?
    /// Maps watched-episode uniqueID → its last watched date, so restores keep
    /// the real "recently watched" ordering instead of resetting to import time.
    let watchedEpisodeDates: [String: Date]?
    /// Per-season taste overrides (seasonNumber → "Love"/"Like"/"Dislike").
    /// Optional so older backups without season likes still decode cleanly.
    let seasonTasteOverrides: [Int: String]?

    // Scalar metadata — carried so a restore doesn't force a full re-fetch.
    let posterURL: String?
    let overview: String?
    let backdropURL: String?
    let releaseDate: Date?
    let lastUpdated: Date?
    let titleLogoURL: String?
    let themeColorHex: String?
    let cachedRuntime: Int?
    let cachedEpisodeRuntime: Int?
    let cachedWatchedEpisodeCount: Int?
    let remainingEpisodesCount: Int?
    let cachedLanguage: String?
    let cachedNetwork: String?
    let cachedNetworkLogoPath: String?
    let mood: String?
}

extension MediaItemData {
    static func canonicalMediaType(for rawValue: String, id: String) -> MediaType {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "tv" || normalized == "tv show" || normalized == "tvshow"
            || normalized == "series" || id.lowercased().hasPrefix("tv_") {
            return .tvShow
        }
        return .movie
    }

    static func canonicalID(_ id: String, type: MediaType) -> String {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let tmdbID = trimmedID.split(separator: "_").last.map(String.init) ?? trimmedID
        let prefix = type == .movie ? "movie" : "tv"
        return "\(prefix)_\(tmdbID)"
    }

    static func importKey(id: String, typeRawValue: String) -> String {
        let type = canonicalMediaType(for: typeRawValue, id: id)
        return "\(canonicalID(id, type: type))_\(type.rawValue)"
    }

    init(item: MediaItem, watchedIDs: [String]?, watchedDates: [String: Date]?) {
        var seasonTaste: [Int: String]? = nil
        if item.type == .tvShow, let tv = item.tvShowDetails {
            let overrides = tv.seasons.liveModels.compactMap { season -> (Int, String)? in
                guard let raw = season.tasteOverrideRaw, season.seasonNumber > 0 else { return nil }
                return (season.seasonNumber, raw)
            }
            if !overrides.isEmpty {
                seasonTaste = Dictionary(uniqueKeysWithValues: overrides)
            }
        }
        self.init(
            id: item.id,
            title: item.title,
            type: item.type?.rawValue ?? "Movie",
            state: item.state?.rawValue ?? "Wishlist",
            dateAdded: item.dateAdded ?? Date(),
            taste: item.tasteValue,
            watchedEpisodeIDs: watchedIDs,
            lastInteractionDate: item.lastInteractionDate,
            watchedEpisodeDates: watchedDates,
            seasonTasteOverrides: seasonTaste,
            posterURL: item.posterURL,
            overview: item.overview.isEmpty ? nil : item.overview,
            backdropURL: item.backdropURL,
            releaseDate: item.releaseDate,
            lastUpdated: item.lastUpdated,
            titleLogoURL: item.titleLogoURL,
            themeColorHex: item.themeColorHex,
            cachedRuntime: item.cachedRuntime,
            cachedEpisodeRuntime: item.cachedEpisodeRuntime,
            cachedWatchedEpisodeCount: item.cachedWatchedEpisodeCount,
            remainingEpisodesCount: item.remainingEpisodesCount,
            cachedLanguage: item.cachedLanguage,
            cachedNetwork: item.cachedNetwork,
            cachedNetworkLogoPath: item.cachedNetworkLogoPath,
            mood: item.mood
        )
    }

    /// Applies the scalar metadata carried in this backup onto a MediaItem (restore path).
    func applyMetadata(to item: MediaItem) {
        if let posterURL, !posterURL.isEmpty { item.posterURL = posterURL }
        if let overview, !overview.isEmpty { item.overview = overview }
        if let backdropURL, !backdropURL.isEmpty { item.backdropURL = backdropURL }
        if let releaseDate { item.releaseDate = releaseDate }
        if let lastUpdated { item.lastUpdated = lastUpdated }
        if let titleLogoURL, !titleLogoURL.isEmpty { item.titleLogoURL = titleLogoURL }
        if let themeColorHex, !themeColorHex.isEmpty { item.themeColorHex = themeColorHex }
        if let cachedRuntime { item.cachedRuntime = cachedRuntime }
        if let cachedEpisodeRuntime { item.cachedEpisodeRuntime = cachedEpisodeRuntime }
        if let cachedWatchedEpisodeCount { item.cachedWatchedEpisodeCount = cachedWatchedEpisodeCount }
        if let remainingEpisodesCount { item.remainingEpisodesCount = remainingEpisodesCount }
        if let cachedLanguage, !cachedLanguage.isEmpty { item.cachedLanguage = cachedLanguage }
        if let cachedNetwork, !cachedNetwork.isEmpty { item.cachedNetwork = cachedNetwork }
        if let cachedNetworkLogoPath, !cachedNetworkLogoPath.isEmpty { item.cachedNetworkLogoPath = cachedNetworkLogoPath }
        if let mood, !mood.isEmpty { item.mood = mood }
    }

    /// Restores per-season taste overrides onto the item's seasons. Creates a
    /// season row if needed so the override isn't lost before a refresh attaches it.
    func applySeasonTasteOverrides(to item: MediaItem, in context: ModelContext, mergeOnlyIfEmpty: Bool = false) {
        guard let overrides = seasonTasteOverrides, !overrides.isEmpty,
              item.type == .tvShow,
              let tmdbID = Int(item.id.split(separator: "_").last ?? "") else { return }

        for (seasonNumber, tasteRaw) in overrides where seasonNumber > 0 {
            let seasonUniqueID = "\(tmdbID)_\(seasonNumber)"
            let sDescriptor = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.uniqueID == seasonUniqueID })
            let season = (try? context.fetch(sDescriptor).first) ?? TVSeason(seasonNumber: seasonNumber, name: "Season \(seasonNumber)", episodeCount: 0, airDate: nil)

            if season.modelContext == nil {
                season.uniqueID = seasonUniqueID
                season.showID = tmdbID
                if let tv = item.tvShowDetails { season.tvShowDetails = tv }
                context.insert(season)
            }
            if mergeOnlyIfEmpty, season.tasteOverrideRaw != nil { continue }
            season.tasteOverrideRaw = tasteRaw
        }
    }
}

struct CollectionBackupData: Codable, Sendable {
    let id: UUID
    let name: String
    let systemImage: String
    let notes: String?
    let isPinned: Bool
    let completedItemIDs: [String]
    let smartRulesData: Data?
    let itemIDs: [String]?
}

struct JSONFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
class LibraryImportExportService {
    static let shared = LibraryImportExportService()
    private init() {}

    func prepareExportData(items: [MediaItem], context: ModelContext) -> Data? {
        let exportItems = items.map { item -> MediaItemData in
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
        if let collections = try? context.fetch(collectionsDescriptor) {
            collectionBackup = collections.map { col in
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try? encoder.encode(backup)
    }

    func automatedBackup(backup: LibraryBackup) async {
        await FileIOActor.shared.run {
            let fm = FileManager.default
            let backupDir = URL.applicationSupportDirectory.appendingPathComponent("AutoBackups")

            do {
                if !fm.fileExists(atPath: backupDir.path) {
                    try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                }

                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let fileName = "MediaTracker_Auto_\(formatter.string(from: Date())).json"
                let fileURL = backupDir.appendingPathComponent(fileName)

                let encoder = JSONEncoder()
                let data = try encoder.encode(backup)
                try data.write(to: fileURL, options: .atomic)
                AppLogger.info("✅ Automated backup saved to \(fileName)", logger: AppLogger.data)

                let files = try fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey])
                var fileInfos = files.compactMap { url -> (URL, Date)? in
                    guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                          let creationDate = attrs[.creationDate] as? Date else { return nil }
                    return (url, creationDate)
                }

                if fileInfos.count > 20 {
                    fileInfos.sort { $0.1 < $1.1 }
                    let itemsToRemove = fileInfos.prefix(fileInfos.count - 20)
                    for item in itemsToRemove {
                        try? fm.removeItem(at: item.0)
                        AppLogger.info("🗑️ Removed old automated backup: \(item.0.lastPathComponent)", logger: AppLogger.data)
                    }
                }

            } catch {
                await MainActor.run { AppErrorState.shared.surfaceError("Backup failed: \(error.localizedDescription)") }
            }
        }
    }

    /// Returns the number of auto-backups and the date of the most recent one.
    static func autoBackupInfo() -> (count: Int, lastDate: Date?) {
        let backupDir = URL.applicationSupportDirectory.appendingPathComponent("AutoBackups")
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey]),
              !files.isEmpty else {
            return (0, nil)
        }
        let infos = files.compactMap { url -> (URL, Date)? in
            guard url.pathExtension == "json",
                  let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let creationDate = attrs[.creationDate] as? Date else { return nil }
            return (url, creationDate)
        }
        let lastDate = infos.map(\.1).max()
        return (infos.count, lastDate)
    }
}
