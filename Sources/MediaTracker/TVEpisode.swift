import Foundation
import SwiftData

@Model
final class TVEpisode {
    var episodeNumber: Int
    var seasonNumber: Int
    var name: String
    var overview: String
    var airDate: String? {
        didSet {
            updateAirDateValue()
        }
    }
    var airstamp: String? {
        didSet {
            updateAirDateValue()
        }
    }
    var airDateValue: Date?
    var runtime: Int?
    var isWatched: Bool = false
    var lastWatchedDate: Date?
    var showID: Int?
    @Attribute(.unique) var uniqueID: String? = nil
    var season: TVSeason?

    func markWatched(_ watched: Bool) {
        if self.isWatched != watched {
            self.isWatched = watched
            if watched {
                self.lastWatchedDate = Date()
            } else {
                self.lastWatchedDate = nil
            }
            
            let delta = watched ? 1 : -1
            season?.watchedEpisodesCount += delta
            
            if let tv = season?.tvShowDetails {
                tv.watchedEpisodesCount += delta
                
                // Update total watched runtime incrementally on the MediaItem
                if let item = tv.item {
                    let epRuntime = self.runtime ?? 0
                    let currentRuntime = item.cachedRuntime ?? 0
                    item.cachedRuntime = max(0, currentRuntime + (watched ? epRuntime : -epRuntime))
                }
                
                // Only adjust remaining count if the episode has already aired
                let now = Date()
                if let airDate = airDateValue, airDate <= now {
                    let oldRemaining = tv.remainingEpisodesCount ?? 0
                    tv.remainingEpisodesCount = max(0, oldRemaining - delta)
                }
            }
        }
    }
    
    // UI property: Uses the persistent airDateValue if accurate, or recalculates
    var airDateAsDate: Date? {
        airDateValue ?? DateUtils.parseEpisodeDate(
            airDate, 
            time: nil, 
            airstamp: airstamp, 
            timezone: season?.tvShowDetails?.timezone, 
            serviceName: season?.tvShowDetails?.network ?? season?.tvShowDetails?.item?.cachedNetwork, 
            for: season?.tvShowDetails
        )
    }

    func updateAirDateValue() {
        self.airDateValue = DateUtils.parseEpisodeDate(
            airDate, 
            time: nil, 
            airstamp: airstamp, 
            timezone: season?.tvShowDetails?.timezone, 
            serviceName: season?.tvShowDetails?.network ?? season?.tvShowDetails?.item?.cachedNetwork, 
            for: season?.tvShowDetails
        )
    }
    
    init(episodeNumber: Int, seasonNumber: Int, name: String, overview: String, airDate: String? = nil, airstamp: String? = nil, runtime: Int? = nil, isWatched: Bool = false, showID: Int? = nil) {
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.airDate = airDate
        self.airstamp = airstamp
        self.runtime = runtime
        self.isWatched = isWatched
        self.showID = showID
        if let showID = showID {
            self.uniqueID = "\(showID)_\(seasonNumber)_\(episodeNumber)"
        } else {
            self.uniqueID = UUID().uuidString
        }
        // Note: airDateValue may still be 00:00 here if network is unknown during init.
        // It gets healed by MaintenanceService or recalculated by airDateAsDate property.
    }
}
