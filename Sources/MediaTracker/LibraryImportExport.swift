import Foundation
import SwiftData
import SwiftUI

struct LibraryBackup: Codable {
    let items: [MediaItemData]
    var version: Int = 1
}

struct MediaItemData: Codable {
    let id: String
    let title: String
    let type: String
    let state: String
    let dateAdded: Date
    let taste: String?
}

@MainActor
class LibraryImportExportService {
    static let shared = LibraryImportExportService()
    private init() {}

    func exportLibrary(items: [MediaItem]) {
        let exportItems = items.map { item in
            MediaItemData(
                id: item.id,
                title: item.title,
                type: item.type?.rawValue ?? "Movie",
                state: item.state?.rawValue ?? "Wishlist",
                dateAdded: item.dateAdded ?? Date(),
                taste: item.tasteValue
            )
        }
        
        let backup = LibraryBackup(items: exportItems)
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MediaTracker_Backup_\(Date().formatted(date: .abbreviated, time: .omitted)).json"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = .prettyPrinted
                    let data = try encoder.encode(backup)
                    try data.write(to: url)
                    print("✅ Library exported to \(url.path)")
                } catch {
                    print("❌ Export error: \(error)")
                }
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

                        print("✅ Library imported successfully: \(count) new items.")
                        AppErrorState.shared.showToast("Imported \(count) items.", systemImage: "tray.and.arrow.down.fill", type: .success)
                        
                        // Automatically start fetching metadata for everything in the library
                        let descriptor = FetchDescriptor<MediaItem>()
                        if let allItems = try? modelContext.fetch(descriptor) {
                            DataService.shared.refreshMetadata(for: allItems, modelContext: modelContext, force: true)
                        }
                        
                        // Run a silent repair to catch any duplicates from the import
                        DataService.shared.runMaintenance(modelContext: modelContext, silent: true)
                    } catch {
                        print("❌ Import error: \(error)")
                        AppErrorState.shared.surfaceError("Failed to import library: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}
