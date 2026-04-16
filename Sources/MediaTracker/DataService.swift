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
    let overview: String
    let posterURL: String?
    let releaseDate: Date?
    let state: String
    let type: String
    let isLiked: Bool?
    let watchHistory: [String: Bool] // EpisodeID: isWatched
}

@MainActor
class DataService {
    static let shared = DataService()
    
    func exportLibrary(items: [MediaItem]) {
        let backupItems = items.map { item in
            var watchHistory: [String: Bool] = [:]
            if let tv = item.tvShowDetails {
                for season in tv.seasons {
                    for episode in season.episodes {
                        if episode.isWatched {
                            watchHistory["\(season.seasonNumber)_\(episode.episodeNumber)"] = true
                        }
                    }
                }
            }
            
            return MediaItemData(
                id: item.id,
                title: item.title,
                overview: item.overview,
                posterURL: item.posterURL,
                releaseDate: item.releaseDate,
                state: item.state?.rawValue ?? "Wishlist",
                type: item.type?.rawValue ?? "Movie",
                isLiked: item.isLiked,
                watchHistory: watchHistory
            )
        }
        
        let backup = LibraryBackup(items: backupItems)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(backup)
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "MediaTracker_Backup.json"
            
            savePanel.begin { result in
                if result == .OK, let url = savePanel.url {
                    try? data.write(to: url)
                }
            }
        } catch {
            print("❌ Export error: \(error)")
        }
    }
    
    @MainActor
    func importLibrary(modelContext: ModelContext) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { result in
            if result == .OK, let url = openPanel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let backup = try decoder.decode(LibraryBackup.self, from: data)
                    
                    for itemData in backup.items {
                        // Avoid duplicates
                        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == itemData.id })
                        let existing = try? modelContext.fetch(descriptor)
                        
                        if existing?.isEmpty ?? true {
                            let item = MediaItem(
                                id: itemData.id,
                                title: itemData.title,
                                overview: itemData.overview,
                                posterURL: itemData.posterURL,
                                releaseDate: itemData.releaseDate,
                                isLiked: itemData.isLiked,
                                state: MediaState(rawValue: itemData.state) ?? .wishlist,
                                type: MediaType(rawValue: itemData.type) ?? .movie
                            )
                            modelContext.insert(item)
                        }
                    }
                    try? modelContext.save()
                } catch {
                    print("❌ Import error: \(error)")
                }
            }
        }
    }
}

