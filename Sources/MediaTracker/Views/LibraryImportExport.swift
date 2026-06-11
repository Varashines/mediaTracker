import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryBackup: Codable, Sendable {
    let items: [MediaItemData]
    var version: Int = 1
}

struct MediaItemData: Codable, Sendable {
    let id: String
    let title: String
    let type: String
    let state: String
    let dateAdded: Date
    let taste: String?
    let watchedEpisodeIDs: [String]?
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

    func prepareExportData(items: [MediaItem]) -> Data? {
        let exportItems = items.map { item -> MediaItemData in
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
}
