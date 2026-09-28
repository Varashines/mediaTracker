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
            // Go through the state setter so this is the in-app path, not a
            // reimplementation of it. The setter records the history event, passes
            // `legacyCompletedAt` so the original completion date is preserved as
            // the first-watch date, and defers the save and broadcast. The manual
            // version previously duplicated all of that and dropped that argument.
            item.state = .completed
            return
        }
        
        guard type == "tvShow", let tvDetails = item.tvShowDetails else { return }
        guard let target = Self.resolveEpisode(tvDetails: tvDetails, season: season, episode: episode) else { return }
        
        // Default `recordHistory: true` records the ledger event and requests the
        // save, matching an in-app mark. The old path passed `recordHistory: false`
        // and then recorded by hand against the background context.
        target.markWatched(true)
        item.syncCachedProperties(dirty: [.progress, .badge])
        // SaveCoordinator is @MainActor-isolated, so this actor commits its own
        // context. Not a hot path: one user-initiated action, one save.
        try modelContext.save()

        Task { @MainActor in
            MediaStateService.shared.postMediaStateChanged()
        }
    }

    /// The episode a "Mark as Watched" notification action should mark.
    ///
    /// Prefers the season/episode carried in the notification, but only when it is
    /// usable: the payload falls back to `0` when the cached next-episode was
    /// missing, and `guard let s = season` happily accepted that `0`, so the lookup
    /// matched nothing and the action reported success while changing nothing.
    private static func resolveEpisode(tvDetails: TVShowDetails, season: Int?, episode: Int?) -> TVEpisode? {
        if let s = season, s > 0, let e = episode, e > 0,
           let match = tvDetails.seasons.liveModels
               .first(where: { $0.seasonNumber == s })?
               .episodes.liveModels
               .first(where: { $0.episodeNumber == e }),
           !match.isWatched {
            return match
        }
        return tvDetails.nextUnwatchedEpisode()
    }
}
