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
    var isWatched: Bool = false {
        didSet {
            if oldValue != isWatched {
                season?.tvShowDetails?.watchedEpisodesCount += (isWatched ? 1 : -1)
            }
        }
    }
    var showID: Int?
    @Attribute(.unique) var uniqueID: String? = nil
    var season: TVSeason?
    
    var airDateAsDate: Date? {
        airDateValue ?? DateUtils.parseEpisodeDate(airDate, time: nil, airstamp: airstamp, timezone: season?.tvShowDetails?.timezone, serviceName: season?.tvShowDetails?.network, for: season?.tvShowDetails)
    }

    func updateAirDateValue() {
        self.airDateValue = DateUtils.parseEpisodeDate(airDate, time: nil, airstamp: airstamp, timezone: season?.tvShowDetails?.timezone, serviceName: season?.tvShowDetails?.network, for: season?.tvShowDetails)
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
        updateAirDateValue()
    }
}
