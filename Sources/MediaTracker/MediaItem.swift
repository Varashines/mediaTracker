import Foundation
import SwiftData

@Model
final class MediaItem: Identifiable {
    var id: String
    var title: String
    var overview: String
    var posterURL: String?
    var backdropURL: String?
    var releaseDate: Date?
    var typeValue: String = "Movie"
    var stateValue: String = "Wishlist"
    var tasteValue: String = "None"
    var themeColorHex: String?
    var lastInteractionDate: Date?
    var lastStateChangeDate: Date?
    var dateAdded: Date?
    var lastUpdated: Date?
    
    // Cached values for filtering/grid
    var cachedGenres: [String] = []
    var cachedCreators: [String] = []
    var cachedLanguage: String?
    var cachedNetwork: String?
    var cachedNetworkLogoPath: String?
    var cachedNextAiringDate: Date?
    var cachedRuntime: Int?
    var cachedWatchedEpisodeCount: Int?
    var remainingEpisodesCount: Int?

    var storedSmartBadgeLabel: String?
    var storedSmartBadgeIcon: String?
    var storedSmartBadgeIsSparkle: Bool = false
    var storedIsUpcoming: Bool = false
    var storedNextEpisodeLabel: String?
    var storedWatchProgressLabel: String?
    var storedProgress: Double?
    var searchableText: String = ""
    var storedCast: [SimpleCastMember] = []
    
    var collections: [MediaCollection]?

    var displayCast: [SimpleCastMember] {
        return storedCast
    }

    init(id: String, title: String, overview: String, posterURL: String? = nil, backdropURL: String? = nil, releaseDate: Date? = nil, type: MediaType? = .movie) {
        self.id = id
        self.title = title
        self.overview = overview
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.releaseDate = releaseDate
        self.typeValue = type?.rawValue ?? "Movie"
        self.lastInteractionDate = Date()
        self.lastStateChangeDate = Date()
        self.dateAdded = Date()
    }

    var type: MediaType? {
        get { MediaType(rawValue: typeValue) }
        set { typeValue = newValue?.rawValue ?? "Movie" }
    }

    var taste: TasteValue? {
        get { TasteValue(rawValue: tasteValue) }
        set { 
            let old = tasteValue
            tasteValue = newValue?.rawValue ?? "None"
            if old != tasteValue {
                lastInteractionDate = Date()
                syncCachedProperties()
            }
        }
    }
    
    var state: MediaState? {
        get { MediaState(rawValue: stateValue) }
        set { 
            let old = stateValue
            stateValue = newValue?.rawValue ?? "Wishlist"
            if old != stateValue {
                lastInteractionDate = Date()
                lastStateChangeDate = Date()
                syncCachedProperties()
            }
        }
    }

    var movieDetails: MovieDetails?
    var tvShowDetails: TVShowDetails?
    
    static func availableStates(for type: MediaType, progress: Double?) -> [MediaState] {
        let progressVal = progress ?? 0
        if progressVal >= 1.0 {
            return [.completed, .rewatching]
        } else if progressVal > 0 {
            return [.active, .onHold, .dropped, .rewatching, .completed]
        }
        // Wishlist is the default for 0 progress
        return MediaState.allCases
    }
}

extension MediaItem {
    var isUpcoming: Bool {
        guard let date = cachedNextAiringDate else { return false }
        return date > Date()
    }

    var badgeText: String? {
        if isUpcoming {
            return cachedNextAiringDate?.formatted(date: .abbreviated, time: .omitted)
        }
        return nil
    }

    var gridBadgeText: String? { badgeText }

    var detailBadgeText: String? {
        if isUpcoming {
            if type == .tvShow {
                return cachedNextAiringDate?.formatted(date: .abbreviated, time: .shortened)
            } else {
                return cachedNextAiringDate?.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return nil
    }

    var requiresMaintenanceRefresh: Bool {
        guard let last = lastUpdated else { return true }
        return Date().timeIntervalSince(last) > (30 * 86400)
    }
}
