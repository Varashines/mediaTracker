import Foundation
import SwiftData
import SwiftUI

enum MediaState: String, Codable, CaseIterable {
    case wishlist = "Wishlist"
    case active = "Active"
    case onHold = "On Hold"
    case dropped = "Dropped"
    case rewatching = "Re-watching"
    case completed = "Completed"
    
    var displayName: String {
        switch self {
        case .wishlist: return "Waitlist"
        case .active: return "In Progress"
        case .onHold: return "On Hold"
        case .dropped: return "Dropped"
        case .rewatching: return "Re-watching"
        case .completed: return "Completed"
        }
    }
}

enum MediaType: String, Codable, CaseIterable {
    case movie = "Movie"
    case tvShow = "TV Show"
    
    var pluralName: String {
        switch self {
        case .movie: return "Movies"
        case .tvShow: return "TV Shows"
        }
    }
}

enum FilterType: String, Codable, Hashable {
    case genre = "Genre"
    case studio = "Studio"
    case language = "Language"
}

enum ThemeStyle: String, Codable, CaseIterable, Identifiable {
    case standard = "Standard"
    case brand = "Brand Blue"
    
    var id: String { self.rawValue }
}

enum AppAccent: String, CaseIterable, Identifiable, Codable {
    case blue = "Blue"
    case indigo = "Indigo"
    case purple = "Purple"
    case rose = "Rose"
    case orange = "Orange"
    case mint = "Mint"
    
    var id: String { self.rawValue }
    
    var color: Color {
        switch self {
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .rose: return .pink
        case .orange: return .orange
        case .mint: return .teal
        }
    }
    
    func brandBackground(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            switch self {
            case .blue: return Color(red: 0.05, green: 0.07, blue: 0.12)
            case .indigo: return Color(red: 0.06, green: 0.05, blue: 0.13)
            case .purple: return Color(red: 0.08, green: 0.04, blue: 0.12)
            case .rose: return Color(red: 0.12, green: 0.04, blue: 0.06)
            case .orange: return Color(red: 0.12, green: 0.07, blue: 0.04)
            case .mint: return Color(red: 0.04, green: 0.09, blue: 0.08)
            }
        } else {
            switch self {
            case .blue: return Color(red: 0.94, green: 0.96, blue: 1.0)
            case .indigo: return Color(red: 0.95, green: 0.94, blue: 1.0)
            case .purple: return Color(red: 0.96, green: 0.94, blue: 1.0)
            case .rose: return Color(red: 1.0, green: 0.94, blue: 0.96)
            case .orange: return Color(red: 1.0, green: 0.96, blue: 0.94)
            case .mint: return Color(red: 0.94, green: 1.0, blue: 0.98)
            }
        }
    }
}

struct DiscoveryFilter: Hashable, Codable {
    let type: FilterType
    let name: String
}

struct DiscoveryNode: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let logoPath: String?
    let count: Int
}

@Model
final class MediaItem {
    var id: String
    var title: String
    var overview: String
    var posterURL: String?
    var releaseDate: Date?
    var lastUpdated: Date?
    var isLiked: Bool?
    var state: MediaState? = MediaState.wishlist
    var type: MediaType? = MediaType.movie
    var themeColorHex: String?
    var dateAdded: Date = Date()
    var searchableText: String = ""
    
    // Type-specific data
    var movieDetails: MovieDetails?
    var tvShowDetails: TVShowDetails?
    
    func updateSearchableText() {
        var components = [title]
        if let movie = movieDetails {
            components.append(contentsOf: movie.genres)
            components.append(contentsOf: movie.cast.prefix(5).map { $0.name })
        } else if let tv = tvShowDetails {
            components.append(contentsOf: tv.genres)
            components.append(contentsOf: tv.cast.prefix(5).map { $0.name })
        }
        self.searchableText = components.joined(separator: " ").lowercased()
    }
    
    var nextAiringDate: Date? {
        guard modelContext != nil else { return nil }
        let currentType = type ?? .movie
        if currentType == .movie {
            return releaseDate
        } else if currentType == .tvShow {
            guard let tv = tvShowDetails else { return nil }
            return tv.oldestUnwatchedEpisodeAirDate ?? tv.nextEpisodeDate
        }
        return nil
    }
    
    /// The absolute next episode to air in the future (regardless of watch history)
    var absoluteNextAiringDate: Date? {
        guard modelContext != nil else { return nil }
        if type == .tvShow {
            return tvShowDetails?.nextEpisodeDate
        }
        return releaseDate
    }
    
    var isRecentlyReleased: Bool {
        guard modelContext != nil else { return false }
        let currentType = type ?? .movie
        
        let dateToCheck: Date?
        if currentType == .tvShow {
            dateToCheck = tvShowDetails?.oldestUnwatchedEpisodeAirDate
        } else {
            dateToCheck = releaseDate
        }

        guard let date = dateToCheck else { return false }
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()
        return date <= Date() && date >= fiveDaysAgo
    }
    
    var isUpcoming: Bool {
        guard modelContext != nil else { return false }
        
        // If it's completed, it's no longer "upcoming" for the user
        if state == .completed { return false }
        
        let airingDate = nextAiringDate
        if let nextDate = airingDate, nextDate > Date() {
            return true
        }
        return isRecentlyReleased
    }
    
    var isActive: Bool {
        guard modelContext != nil else { return false }
        let currentType = type ?? .movie
        let currentState = state ?? .wishlist
        
        if currentState == .onHold || currentState == .dropped || currentState == .rewatching {
            return false
        }
        
        if currentType == .tvShow, let tv = tvShowDetails {
            return tv.cachedHasWatchedAnyEpisode && !tv.cachedHasWatchedAllEpisodes
        } else if currentType == .movie {
            return currentState == .active
        }
        return false
    }
    
    var genres: [String] {
        guard modelContext != nil else { return [] }
        if let movie = movieDetails {
            return movie.genres
        } else if let tv = tvShowDetails {
            return tv.genres
        }
        return []
    }

    var nextAiringLabel: String? {
        guard modelContext != nil else { return nil }
        guard let date = nextAiringDate else { return isRecentlyReleased ? "Available Now" : nil }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        
        if date > Date() {
            if type == .movie {
                return "Releases \(formatter.string(from: date))"
            } else if type == .tvShow {
                if let tv = tvShowDetails {
                    let s = tv.nextSeasonNumber ?? 1
                    let e = tv.nextEpisodeNumber ?? 1
                    if e == 1 {
                        return "S\(s) Premiere: \(formatter.string(from: date))"
                    }
                    return "S\(s), E\(e): \(formatter.string(from: date))"
                }
            }
        }
        return isRecentlyReleased ? "Available Now" : nil
    }

    var watchProgressLabel: String? {
        guard modelContext != nil else { return state?.displayName }
        if type == .tvShow, let tv = tvShowDetails {
            return tv.cachedWatchProgressLabel ?? state?.displayName
        }
        return state?.displayName
    }
    
    var hasWatchedAnyEpisode: Bool {
        guard modelContext != nil else { return false }
        if type == .tvShow, let tv = tvShowDetails {
            return tv.cachedHasWatchedAnyEpisode
        }
        return false
    }

    var hasWatchedAllEpisodes: Bool {
        guard modelContext != nil else { return false }
        if type == .tvShow, let tv = tvShowDetails {
            return tv.cachedHasWatchedAllEpisodes
        }
        return false
    }

    var nextEpisodeToWatchLabel: String? {
        guard modelContext != nil, type == .tvShow, let tv = tvShowDetails else { return nil }
        return tv.cachedNextEpisodeToWatchLabel
    }

    /// Determines if a TV show needs a background refresh (older than 30 days and not finished)
    var requiresMaintenanceRefresh: Bool {
        guard type == .tvShow, let status = tvShowDetails?.status else { return false }
        
        // Don't auto-refresh ended or cancelled shows
        let finalizedStatuses = ["Ended", "Canceled", "Cancelled"]
        if finalizedStatuses.contains(where: { status.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
            return false
        }
        
        guard let lastUpdated = lastUpdated else { return true }
        let thirtyDays: TimeInterval = 30 * 24 * 60 * 60
        return Date().timeIntervalSince(lastUpdated) > thirtyDays
    }
    
    init(id: String, title: String, overview: String, posterURL: String? = nil, releaseDate: Date? = nil, isLiked: Bool? = nil, state: MediaState? = .wishlist, type: MediaType? = .movie) {
        self.id = id
        self.title = title
        self.overview = overview
        self.posterURL = posterURL
        self.releaseDate = releaseDate
        self.isLiked = isLiked
        self.state = state
        self.type = type
    }
    
    @MainActor
    func checkOverallCompletion() {
        guard type == .tvShow, let tv = tvShowDetails else { return }
        let totalEpisodes = tv.seasons.reduce(0) { $0 + $1.episodeCount }
        let watchedEpisodes = tv.seasons.reduce(0) { $0 + $1.episodes.filter { $0.isWatched }.count }
        
        if totalEpisodes > 0 {
            if watchedEpisodes >= totalEpisodes {
                state = .completed
                NotificationManager.shared.cancelNotification(for: self)
            } else if watchedEpisodes > 0 {
                if state == .wishlist || state == .completed {
                    state = .active
                }
            }
        }
    }
}

@Model
final class MovieDetails {
    var tmdbID: Int
    var runtime: Int?
    var genres: [String]
    var voteAverage: Double?
    var originalLanguage: String?
    @Relationship(deleteRule: .cascade) var cast: [CastMember] = []
    
    init(tmdbID: Int, runtime: Int? = nil, genres: [String] = [], voteAverage: Double? = nil, originalLanguage: String? = nil) {
        self.tmdbID = tmdbID
        self.runtime = runtime
        self.genres = genres
        self.voteAverage = voteAverage
        self.originalLanguage = originalLanguage
    }
}

@Model
final class TVShowDetails {
    var tmdbID: Int
    var tvdbID: Int?
    var tvMazeID: Int?
    var nextEpisodeDate: Date?
    var nextEpisodeTime: String?
    var nextEpisodeName: String?
    var nextEpisodeNumber: Int?
    var nextSeasonNumber: Int?
    var status: String?
    var network: String?
    var networkLogoPath: String?
    var originalLanguage: String?
    var timezone: String?
    var numberOfSeasons: Int?
    var numberOfEpisodes: Int?
    var voteAverage: Double?
    var genres: [String] = []
    
    @Relationship(deleteRule: .cascade) var seasons: [TVSeason] = []
    @Relationship(deleteRule: .cascade) var cast: [CastMember] = []
    
    // Performance Cache (Prevents heavy loops during scrolling)
    var cachedWatchProgressLabel: String?
    var cachedNextEpisodeToWatchLabel: String?
    var cachedHasWatchedAnyEpisode: Bool = false
    var cachedHasWatchedAllEpisodes: Bool = false
    
    func recalculateCachedProperties() {
        let sortedSeasons = seasons.sorted { $0.seasonNumber < $1.seasonNumber }
        let allEpisodes = sortedSeasons.flatMap { $0.episodes.sorted { $0.episodeNumber < $1.episodeNumber } }
        
        let totalCount = sortedSeasons.reduce(0) { $0 + $1.episodeCount }
        let watchedCount = allEpisodes.filter { $0.isWatched }.count
        
        self.cachedWatchProgressLabel = "\(watchedCount)/\(totalCount)"
        self.cachedHasWatchedAnyEpisode = watchedCount > 0
        self.cachedHasWatchedAllEpisodes = totalCount > 0 && watchedCount >= totalCount
        
        if let next = allEpisodes.first(where: { !$0.isWatched }), let season = next.season {
            self.cachedNextEpisodeToWatchLabel = "S\(season.seasonNumber), E\(next.episodeNumber)"
        } else {
            self.cachedNextEpisodeToWatchLabel = nil
        }
    }
    
    var oldestUnwatchedEpisodeAirDate: Date? {
        let allEpisodes = seasons.flatMap { $0.episodes }
        let unwatched = allEpisodes.filter { !$0.isWatched }
        let dates = unwatched.compactMap { $0.airDateAsDate }
        return dates.min()
    }
    
    init(tmdbID: Int, tvdbID: Int? = nil, tvMazeID: Int? = nil, nextEpisodeDate: Date? = nil, nextEpisodeTime: String? = nil, nextEpisodeName: String? = nil, nextEpisodeNumber: Int? = nil, nextSeasonNumber: Int? = nil, status: String? = nil, network: String? = nil, networkLogoPath: String? = nil, originalLanguage: String? = nil, timezone: String? = nil, numberOfSeasons: Int? = nil, numberOfEpisodes: Int? = nil, voteAverage: Double? = nil, genres: [String] = []) {
        self.tmdbID = tmdbID
        self.tvdbID = tvdbID
        self.tvMazeID = tvMazeID
        self.nextEpisodeDate = nextEpisodeDate
        self.nextEpisodeTime = nextEpisodeTime
        self.nextEpisodeName = nextEpisodeName
        self.nextEpisodeNumber = nextEpisodeNumber
        self.nextSeasonNumber = nextSeasonNumber
        self.status = status
        self.network = network
        self.networkLogoPath = networkLogoPath
        self.originalLanguage = originalLanguage
        self.timezone = timezone
        self.numberOfSeasons = numberOfSeasons
        self.numberOfEpisodes = numberOfEpisodes
        self.voteAverage = voteAverage
        self.genres = genres
    }
}

@Model
final class CastMember: Identifiable {
    var name: String
    var characterName: String
    var profileURL: String?
    var order: Int
    
    init(name: String, characterName: String, profileURL: String? = nil, order: Int = 0) {
        self.name = name
        self.characterName = characterName
        self.profileURL = profileURL
        self.order = order
    }
}

@Model
final class TVSeason {
    var seasonNumber: Int
    var name: String
    var episodeCount: Int
    var airDate: String?
    var tvShowDetails: TVShowDetails?
    @Relationship(deleteRule: .cascade) var episodes: [TVEpisode] = []
    
    init(seasonNumber: Int, name: String, episodeCount: Int, airDate: String? = nil) {
        self.seasonNumber = seasonNumber
        self.name = name
        self.episodeCount = episodeCount
        self.airDate = airDate
    }
}

@Model
final class TVEpisode {
    var episodeNumber: Int
    var seasonNumber: Int
    var name: String
    var overview: String
    var airDate: String?
    var airstamp: String?
    var runtime: Int?
    var isWatched: Bool = false
    var season: TVSeason?
    
    var airDateAsDate: Date? {
        DateUtils.parseEpisodeDate(airDate, time: nil, airstamp: airstamp, timezone: season?.tvShowDetails?.timezone, serviceName: season?.tvShowDetails?.network, for: season?.tvShowDetails)
    }
    
    init(episodeNumber: Int, seasonNumber: Int, name: String, overview: String, airDate: String? = nil, airstamp: String? = nil, runtime: Int? = nil, isWatched: Bool = false) {
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.airDate = airDate
        self.airstamp = airstamp
        self.runtime = runtime
        self.isWatched = isWatched
    }
}
