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
            let oldState = item.state
            let now = Date()
            item.stateValue = MediaState.completed.rawValue
            item.lastInteractionDate = now
            item.lastStateChangeDate = now
            WatchHistoryCoordinator.handleStateChange(
                item: item,
                from: oldState,
                to: .completed,
                context: modelContext,
                now: now
            )
        } else if type == "tvShow", let s = season, let e = episode {
            if let tvDetails = item.tvShowDetails {
                seasonLoop: for seasonObj in tvDetails.seasons where seasonObj.seasonNumber == s {
                    for episodeObj in seasonObj.episodes where episodeObj.episodeNumber == e {
                        let now = Date()
                        episodeObj.markWatched(true, recordHistory: false)
                        let episodeID = episodeObj.uniqueID ?? "\(item.id)_\(s)_\(e)"
                        WatchHistoryCoordinator.recordEpisodeMutation(
                            mediaID: item.id,
                            episodeID: episodeID,
                            watchedAt: episodeObj.watchedDate ?? now,
                            runtimeMinutes: episodeObj.runtime,
                            isWatched: true,
                            context: modelContext,
                            source: .manual
                        )
                        break seasonLoop
                    }
                }
            }
        }
        
        item.syncCachedProperties(dirty: [.progress, .badge])
        try modelContext.save()
        
        // Notify UI
        Task { @MainActor in
            MediaStateService.shared.postMediaStateChanged()
        }
    }
}
