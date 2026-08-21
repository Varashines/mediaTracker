import Foundation
import SwiftData
import os

/// Focused service for TV episode-progress side effects triggered by state
/// changes (e.g. completing a show auto-marks all episodes watched).
///
/// Cached per `ModelContainer` (same pattern as `MediaFilterActor.shared`)
/// so state changes don't allocate a fresh `@ModelActor` per call. The heavy
/// refresh/populate logic stays on `BackgroundDataService`; this service owns
/// a single long-lived instance of it for this use case only.
@ModelActor
actor EpisodeProgressService {
    private var refreshService: BackgroundDataService?

    func markAllEpisodesWatched(itemID: String) async {
        let service: BackgroundDataService
        if let cached = refreshService {
            service = cached
        } else {
            service = BackgroundDataService(modelContainer: modelContainer)
            refreshService = service
        }
        await service.markAllEpisodesAsWatched(itemID: itemID)
    }
}

private struct CachedEpisodeProgressService {
    let containerID: ObjectIdentifier
    let service: EpisodeProgressService
}

private let _episodeProgressCache = OSAllocatedUnfairLock<CachedEpisodeProgressService?>(uncheckedState: nil)

extension EpisodeProgressService {
    static func shared(modelContainer: ModelContainer) -> EpisodeProgressService {
        let containerID = ObjectIdentifier(modelContainer)
        return _episodeProgressCache.withLockUnchecked { state in
            if let cached = state, cached.containerID == containerID {
                return cached.service
            }
            let service = EpisodeProgressService(modelContainer: modelContainer)
            state = CachedEpisodeProgressService(containerID: containerID, service: service)
            return service
        }
    }
}
