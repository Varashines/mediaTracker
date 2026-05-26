import Foundation
import SwiftData
import SwiftUI

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

@MainActor
class LibraryImportExportService {
    static let shared = LibraryImportExportService()
    private init() {}

    func exportLibrary(items: [MediaItem]) {
        // Map items to Sendable structs on the MainActor before crossing boundaries
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

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MediaTracker_Backup_\(Date().formatted(date: .abbreviated, time: .omitted)).json"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                // Offload encoding + disk write to FileIOActor to avoid blocking MainActor
                Task.detached(priority: .userInitiated) {
                    await FileIOActor.shared.run {
                        do {
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = .prettyPrinted
                            let data = try encoder.encode(backup)
                            try data.write(to: url, options: .atomic)
                            AppLogger.info("✅ Library exported to \(url.path)", logger: AppLogger.data)
                        } catch {
                            await MainActor.run { AppErrorState.shared.surfaceError("Export failed: \(error.localizedDescription)") }
                        }
                    }
                }
            }
        }
    }

    /// Accepts a pre-built Sendable `LibraryBackup` struct so callers can map
    /// non-Sendable `MediaItem` models to value types on their own context/actor
    /// before crossing the MainActor boundary.
    func automatedBackup(backup: LibraryBackup) async {
        // Offload all filesystem and serialization work to FileIOActor
        await FileIOActor.shared.run {
            let fm = FileManager.default
            let backupDir = URL.applicationSupportDirectory.appendingPathComponent("AutoBackups")

            do {
                if !fm.fileExists(atPath: backupDir.path) {
                    try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                }

                // Format: MediaTracker_Auto_yyyy-MM-dd_HH-mm-ss.json
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let fileName = "MediaTracker_Auto_\(formatter.string(from: Date())).json"
                let fileURL = backupDir.appendingPathComponent(fileName)

                let encoder = JSONEncoder()
                let data = try encoder.encode(backup)
                try data.write(to: fileURL, options: .atomic)
                AppLogger.info("✅ Automated backup saved to \(fileName)", logger: AppLogger.data)

                // Enforce rolling limit (keep last 20)
                let files = try fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey])
                var fileInfos = files.compactMap { url -> (URL, Date)? in
                    guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                          let creationDate = attrs[.creationDate] as? Date else { return nil }
                    return (url, creationDate)
                }

                if fileInfos.count > 20 {
                    // Sort oldest first
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

    func importLibrary(modelContext: ModelContext) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let container = modelContext.container

                Task {
                    do {
                        // 1. Offload Heavy File I/O and Decoding
                        let backup = try await Task.detached(priority: .userInitiated) {
                            let data = try Data(contentsOf: url)
                            return try JSONDecoder().decode(LibraryBackup.self, from: data)
                        }.value

                        // 2. Hand over to Background Actor for DB Inserts
                        let backgroundService = BackgroundDataService(modelContainer: container)
                        let count = await backgroundService.importLibraryData(backup: backup)

                        AppLogger.info("✅ Library imported successfully: \(count) new items.", logger: AppLogger.data)
                        AppErrorState.shared.showToast("Imported \(count) items.", systemImage: "tray.and.arrow.down.fill", type: .success)
                        
                        // Automatically start fetching metadata for everything in the library
                        let descriptor = FetchDescriptor<MediaItem>()
                        if let allItems = try? modelContext.fetch(descriptor) {
                            DataService.shared.refreshMetadata(for: allItems, modelContext: modelContext, force: true)
                        }
                        
                        // Run a silent repair to catch any duplicates from the import
                        DataService.shared.runMaintenance(modelContext: modelContext, silent: true)
                    } catch {
                        await MainActor.run {
                            AppErrorState.shared.surfaceError("Import failed: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}
