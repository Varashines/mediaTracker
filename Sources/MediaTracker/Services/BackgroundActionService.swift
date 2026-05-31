import Foundation
import SwiftData
import SwiftUI

/// Handles high-priority background actions like those triggered by notifications.
@ModelActor
actor BackgroundActionService {
    func markAsWatched(itemID: String, type: String, season: Int? = nil, episode: Int? = nil) throws {
        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate<MediaItem> { $0.id == itemID })
        guard let item = try modelContext.fetch(descriptor).first else { return }
        
        if type == "movie" {
            item.state = .completed
        } else if type == "tvShow", let s = season, let e = episode {
            // Find specific episode
            if let tvDetails = item.tvShowDetails {
                for seasonObj in tvDetails.seasons where seasonObj.seasonNumber == s {
                    for episodeObj in seasonObj.episodes where episodeObj.episodeNumber == e {
                        episodeObj.markWatched(true)
                        break
                    }
                }
            }
        }
        
        item.syncCachedProperties()
        try modelContext.save()
        
        // Notify UI
        Task { @MainActor in
            MediaStateService.shared.postMediaStateChanged()
        }
    }
}
