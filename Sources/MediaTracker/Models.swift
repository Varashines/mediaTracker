import Foundation
import SwiftData
import SwiftUI

// Phase 3 Optimization: String Interning (Flyweight Pattern)
// Shared actor to ensure common strings only occupy memory once.
actor StringPool {
    static let shared = StringPool()
    private var pool: Set<String> = []

    func intern(_ string: String?) -> String? {
        guard let string = string, !string.isEmpty else { return nil }
        
        if let existing = pool.first(where: { $0 == string }) {
            return existing
        }
        
        pool.insert(string)
        return string
    }
}

enum MediaState: String, Codable, CaseIterable {
    case wishlist = "Wishlist"
    case active = "Active"
    case onHold = "On Hold"
    case dropped = "Dropped"
    case rewatching = "Re-watching"
    case completed = "Completed"
    
    var displayName: String {
        switch self {
        case .wishlist: return "Watchlist"
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
            case .blue: return Color(red: 0.08, green: 0.12, blue: 0.24)
            case .indigo: return Color(red: 0.12, green: 0.08, blue: 0.28)
            case .purple: return Color(red: 0.16, green: 0.08, blue: 0.24)
            case .rose: return Color(red: 0.24, green: 0.08, blue: 0.12)
            case .orange: return Color(red: 0.24, green: 0.12, blue: 0.08)
            case .mint: return Color(red: 0.08, green: 0.2, blue: 0.16)
            }
        } else {
            switch self {
            case .blue: return Color(red: 0.97, green: 0.98, blue: 1.0)
            case .indigo: return Color(red: 0.97, green: 0.97, blue: 1.0)
            case .purple: return Color(red: 0.98, green: 0.97, blue: 1.0)
            case .rose: return Color(red: 1.0, green: 0.97, blue: 0.98)
            case .orange: return Color(red: 1.0, green: 0.98, blue: 0.97)
            case .mint: return Color(red: 0.97, green: 1.0, blue: 0.99)
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

extension Notification.Name {
    static let mediaStateChanged = Notification.Name("mediaStateChanged")
}

@Model
final class MediaItem {
    var id: String
    var title: String
    @Attribute(.externalStorage) var overview: String
    var posterURL: String?
    var releaseDate: Date?
    var lastUpdated: Date?
    var isLiked: Bool?
    var state: MediaState? = MediaState.wishlist
    var type: MediaType? = MediaType.movie
    var themeColorHex: String?
    var cachedGenres: [String] = []
    var cachedNetwork: String?
    var cachedLanguage: String?

    var cachedNextAiringDate: Date?
    var dateAdded: Date = Date()
    var lastInteractionDate: Date?
    var lastStateChangeDate: Date = Date()
    @Attribute(.externalStorage) var searchableText: String = ""
    
    // Type-specific data
    var movieDetails: MovieDetails?
    var tvShowDetails: TVShowDetails?
    
    func syncCachedProperties() {
        if let movie = movieDetails {
            self.cachedGenres = movie.genres
            self.cachedNetwork = nil
            self.cachedLanguage = movie.originalLanguage
            self.cachedNextAiringDate = releaseDate
        } else if let tv = tvShowDetails {
            self.cachedGenres = tv.genres
            self.cachedNetwork = tv.network
            self.cachedLanguage = tv.originalLanguage
            self.cachedNextAiringDate = tv.oldestUnwatchedEpisodeAirDate ?? tv.nextEpisodeDate
        }
    }

    func updateSearchableText() {
        syncCachedProperties()
        
        var components = [title]
        components.append(contentsOf: cachedGenres)
        
        if let network = cachedNetwork {
            components.append(network)
        }
        
        if let languageCode = cachedLanguage {
            let localizedLanguage = Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode
            components.append(localizedLanguage)
        }

        if let movie = movieDetails {
            components.append(contentsOf: movie.creators)
            components.append(contentsOf: movie.cast.prefix(5).map { $0.name })
        } else if let tv = tvShowDetails {
            components.append(contentsOf: tv.creators)
            components.append(contentsOf: tv.cast.prefix(5).map { $0.name })
        }
        self.searchableText = components.joined(separator: " ").lowercased()
    }
    
    var genres: [String] {
        return cachedGenres
    }
    
    var nextAiringDate: Date? {
        return cachedNextAiringDate
    }
    
    /// The absolute next episode to air in the future (regardless of watch history)
    var absoluteNextAiringDate: Date? {
        if type == .tvShow {
            return tvShowDetails?.nextEpisodeDate
        }
        return releaseDate
    }
    
    var isRecentlyReleased: Bool {
        guard let date = cachedNextAiringDate else { return false }
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()
        return date <= Date() && date >= fiveDaysAgo
    }
    
    var isUpcoming: Bool {
        guard modelContext != nil else { return false }

        // If it's completed, it's no longer "upcoming" for the user
        if state == .completed { return false }

        // nextAiringDate for TV shows is already the first unwatched episode air date.
        // For movies, it's the release date.
        guard let date = nextAiringDate else { return false }

        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()

        // Show is upcoming if it's in the future OR it aired in the last 5 days (and we haven't watched it)
        return date >= fiveDaysAgo
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
    
    private var baseBadgeComponents: (epInfo: String, dateString: String?, isAvailable: Bool)? {
        guard modelContext != nil else { return nil }
        
        if type == .movie {
            guard let date = nextAiringDate else { 
                return isRecentlyReleased ? ("", "Now Streaming", true) : nil 
            }
            let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()
            if date < fiveDaysAgo { return nil }
            
            let isAvailable = date <= Date()
            let ds: String
            if isAvailable {
                ds = "Now Streaming"
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none
                ds = "Releases \(formatter.string(from: date))"
            }
            return (epInfo: "", dateString: ds, isAvailable: isAvailable)
        } else if type == .tvShow {
            guard let tv = tvShowDetails else { return nil }
            
            let sortedSeasons = tv.seasons.sorted { $0.seasonNumber < $1.seasonNumber }
            let allEpisodes = sortedSeasons.flatMap { $0.episodes.sorted { $0.episodeNumber < $1.episodeNumber } }
            let unwatched = allEpisodes.filter { !$0.isWatched }
            
            let ep: (season: Int, episode: Int, date: Date?, isTrueFullSeason: Bool)
            if let next = unwatched.first {
                var isBingeDrop = false
                
                // TRUE FULL SEASON LOGIC: 
                // 1. Next episode is E1
                // 2. Season has > 1 episode
                // 3. First and last episode dates match
                if next.episodeNumber == 1, let season = next.season, season.episodeCount > 1 {
                    let sortedEpisodes = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
                    if let firstDate = sortedEpisodes.first?.airDateAsDate,
                       let lastDate = sortedEpisodes.last?.airDateAsDate,
                       abs(firstDate.timeIntervalSince(lastDate)) < 86400 { // Same day
                        isBingeDrop = true
                    }
                }
                
                ep = (next.seasonNumber, next.episodeNumber, next.airDateAsDate, isBingeDrop)
            } else if let s = tv.nextSeasonNumber, let e = tv.nextEpisodeNumber, let d = tv.nextEpisodeDate {
                ep = (s, e, d, false) // Fallback for future known next episode
            } else {
                return nil
            }
            
            let isAvailable = ep.date != nil && ep.date! <= Date()
            
            if ep.isTrueFullSeason {
                let ds = isAvailable ? "Now Streaming" : ep.date?.formatted(date: .abbreviated, time: .omitted) ?? ""
                return (epInfo: "🍿 Season \(ep.season)\(isAvailable ? "" : " Drops")", dateString: ds, isAvailable: isAvailable)
            } else {
                let ds: String?
                if isAvailable {
                    ds = "Now Streaming"
                } else if let d = ep.date {
                    ds = d.formatted(date: .abbreviated, time: .shortened)
                } else {
                    ds = nil
                }
                return (epInfo: "S\(ep.season), E\(ep.episode)", dateString: ds, isAvailable: isAvailable)
            }
        }
        return nil
    }

    var gridBadgeText: String? {
        guard let comps = baseBadgeComponents else { return nil }
        if comps.epInfo.isEmpty { return comps.dateString }
        if let ds = comps.dateString {
            return "\(comps.epInfo)\n\(ds)"
        }
        return comps.epInfo
    }

    var detailBadgeText: String? {
        guard let comps = baseBadgeComponents else { return nil }
        if comps.epInfo.isEmpty { return comps.dateString }
        if let ds = comps.dateString {
            return "\(comps.epInfo): \(ds)"
        }
        return comps.epInfo
    }

    var badgeText: String? { gridBadgeText }

    var watchProgressLabel: String? {
        guard modelContext != nil else { return state?.displayName }
        if type == .tvShow, let tv = tvShowDetails {
            return tv.cachedWatchProgressLabel ?? state?.displayName
        }
        return state?.displayName
    }
    
    var progress: Double? {
        if type == .tvShow {
            return tvShowDetails?.cachedProgress
        }
        return nil
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
            lastInteractionDate = Date()
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
    var creators: [String] = []
    
    @Relationship(inverse: \MediaItem.movieDetails)
    var item: MediaItem? // Relationship back to parent

    @Relationship(deleteRule: .cascade) var cast: [CastMember] = []
    
    init(tmdbID: Int, runtime: Int? = nil, genres: [String] = [], voteAverage: Double? = nil, originalLanguage: String? = nil, creators: [String] = []) {
        self.tmdbID = tmdbID
        self.runtime = runtime
        self.genres = genres
        self.voteAverage = voteAverage
        self.originalLanguage = originalLanguage
        self.creators = creators
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
    var creators: [String] = []

    @Relationship(inverse: \MediaItem.tvShowDetails)
    var item: MediaItem? // Relationship back to parent

    @Relationship(deleteRule: .cascade) var seasons: [TVSeason] = []
    @Relationship(deleteRule: .cascade) var cast: [CastMember] = []
    
    // Performance Cache (Prevents heavy loops during scrolling)
    var cachedWatchProgressLabel: String?
    var cachedNextEpisodeToWatchLabel: String?
    var cachedHasWatchedAnyEpisode: Bool = false
    var cachedHasWatchedAllEpisodes: Bool = false
    var cachedOldestUnwatchedEpisodeAirDate: Date?
    var cachedProgress: Double?
    
    func recalculateCachedProperties(triggerSync: Bool = false) {
        let sortedSeasons = seasons.sorted { $0.seasonNumber < $1.seasonNumber }
        
        // Phase 2 Fix: Find the first season with unwatched episodes
        // We look for a season where not all episodes are watched, OR a season that has zero episodes loaded (yet)
        if let currentSeason = sortedSeasons.first(where: { s in 
            let unwatchedInSeason = s.episodes.filter { !$0.isWatched }
            return !unwatchedInSeason.isEmpty || s.episodeCount == 0
        }) {
            let seasonWatched = currentSeason.episodes.filter { $0.isWatched }.count
            // If episodes aren't loaded yet, show 0/total for that season
            let totalInSeason = currentSeason.episodeCount > 0 ? currentSeason.episodeCount : 0
            self.cachedWatchProgressLabel = "S\(currentSeason.seasonNumber), \(seasonWatched)/\(totalInSeason)"
            self.cachedHasWatchedAnyEpisode = seasonWatched > 0 || seasons.contains(where: { $0.seasonNumber < currentSeason.seasonNumber })
            self.cachedHasWatchedAllEpisodes = false
            self.cachedProgress = totalInSeason > 0 ? Double(seasonWatched) / Double(totalInSeason) : 0.0
        } else {
            // Everything is watched, or no seasons exist
            let allEpisodes = sortedSeasons.flatMap { $0.episodes }
            let totalWatched = allEpisodes.filter { $0.isWatched }.count
            let totalCount = sortedSeasons.reduce(0) { $0 + $1.episodeCount }
            self.cachedWatchProgressLabel = "\(totalWatched)/\(totalCount)"
            self.cachedHasWatchedAnyEpisode = totalWatched > 0
            self.cachedHasWatchedAllEpisodes = totalCount > 0 && totalWatched >= totalCount
            self.cachedProgress = totalCount > 0 ? Double(totalWatched) / Double(totalCount) : 0.0
        }
        
        // Badge Logic Sync
        let allEpisodes = sortedSeasons.flatMap { $0.episodes.sorted { $0.episodeNumber < $1.episodeNumber } }
        let unwatched = allEpisodes.filter { !$0.isWatched }
        
        if let next = unwatched.first, let season = next.season {
            self.cachedNextEpisodeToWatchLabel = "S\(season.seasonNumber), E\(next.episodeNumber)"
            self.cachedOldestUnwatchedEpisodeAirDate = next.airDateAsDate
        } else {
            self.cachedNextEpisodeToWatchLabel = nil
            self.cachedOldestUnwatchedEpisodeAirDate = nil
        }
        
        if triggerSync {
            self.item?.syncCachedProperties()
            self.item?.lastStateChangeDate = Date()
        }
    }
    
    var oldestUnwatchedEpisodeAirDate: Date? {
        return cachedOldestUnwatchedEpisodeAirDate
    }
    
    init(tmdbID: Int, tvdbID: Int? = nil, tvMazeID: Int? = nil, nextEpisodeDate: Date? = nil, nextEpisodeTime: String? = nil, nextEpisodeName: String? = nil, nextEpisodeNumber: Int? = nil, nextSeasonNumber: Int? = nil, status: String? = nil, network: String? = nil, networkLogoPath: String? = nil, originalLanguage: String? = nil, timezone: String? = nil, numberOfSeasons: Int? = nil, numberOfEpisodes: Int? = nil, voteAverage: Double? = nil, genres: [String] = [], creators: [String] = []) {
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
        self.creators = creators
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
    @Attribute(.externalStorage) var overview: String
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
