import Foundation
import SwiftData
import SwiftUI

// Phase 3 Optimization: String Interning (Flyweight Pattern)
// While currently internal to Models.swift, it ensures unique string instances for common metadata.
actor StringPool {
    static let shared = StringPool()
    private var pool: Set<String> = []
    private let maxPoolSize = 5000

    private init() {
        NotificationCenter.default.addObserver(forName: .memoryPressureWarning, object: nil, queue: nil) { _ in
            Task { await StringPool.shared.clear() }
        }
    }

    func intern(_ string: String?) -> String? {
        guard let string = string, !string.isEmpty else { return nil }
        if let existing = pool.first(where: { $0 == string }) { return existing }
        if pool.count >= maxPoolSize { pool.removeAll() }
        pool.insert(string)
        return string
    }

    func clear() { pool.removeAll() }
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

    var iconName: String {
        switch self {
        case .wishlist: return "clock.fill"
        case .active: return "play.circle.fill"
        case .onHold: return "pause.circle.fill"
        case .dropped: return "xmark.bin.fill"
        case .rewatching: return "arrow.clockwise"
        case .completed: return "checkmark.circle.fill"
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
    case cosmic = "Cosmic"
    case solar = "Solar"
    case neon = "Neon"
    case berry = "Berry"
    case minty = "Minty"
    case honey = "Honey"
    case candy = "Candy"
    case lava = "Lava"

    var id: String { self.rawValue }

    var color: Color {
        switch self {
        case .cosmic: return Color(red: 0.55, green: 0.35, blue: 0.95)
        case .solar: return Color(red: 1.00, green: 0.45, blue: 0.20)
        case .neon: return Color(red: 0.00, green: 0.85, blue: 0.95)
        case .berry: return Color(red: 0.85, green: 0.15, blue: 0.45)
        case .minty: return Color(red: 0.00, green: 0.80, blue: 0.60)
        case .honey: return Color(red: 1.00, green: 0.75, blue: 0.00)
        case .candy: return Color(red: 1.00, green: 0.40, blue: 0.70)
        case .lava: return Color(red: 1.00, green: 0.20, blue: 0.30)
        }
    }

    func brandBackground(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            switch self {
            case .cosmic: return Color(red: 0.12, green: 0.08, blue: 0.25)
            case .solar: return Color(red: 0.25, green: 0.12, blue: 0.08)
            case .neon: return Color(red: 0.08, green: 0.20, blue: 0.24)
            case .berry: return Color(red: 0.22, green: 0.08, blue: 0.16)
            case .minty: return Color(red: 0.08, green: 0.22, blue: 0.18)
            case .honey: return Color(red: 0.24, green: 0.20, blue: 0.08)
            case .candy: return Color(red: 0.24, green: 0.10, blue: 0.18)
            case .lava: return Color(red: 0.25, green: 0.08, blue: 0.10)
            }
        } else {
            switch self {
            case .cosmic: return Color(red: 0.97, green: 0.96, blue: 1.0)
            case .solar: return Color(red: 1.0, green: 0.98, blue: 0.96)
            case .neon: return Color(red: 0.96, green: 1.0, blue: 1.0)
            case .berry: return Color(red: 1.0, green: 0.96, blue: 0.98)
            case .minty: return Color(red: 0.96, green: 1.0, blue: 0.98)
            case .honey: return Color(red: 1.0, green: 0.99, blue: 0.96)
            case .candy: return Color(red: 1.0, green: 0.96, blue: 0.99)
            case .lava: return Color(red: 1.0, green: 0.96, blue: 0.96)
            }
        }
    }
}

struct DiscoveryFilter: Hashable, Codable {
    let type: FilterType
    let name: String
}

struct DiscoveryNode: Identifiable, Equatable, Codable {
    var id: String { code ?? name }
    let name: String
    var code: String? = nil
    let logoPath: String?
    let count: Int
    var themeColorHex: String? = nil
}

@Model
final class NetworkEntity {
    var name: String
    var logoPath: String?
    var count: Int = 0
    var themeColorHex: String?

    init(name: String, logoPath: String?, count: Int = 1) {
        self.name = name
        self.logoPath = logoPath
        self.count = count
    }
}

@Model
final class GenreEntity {
    var name: String
    var count: Int = 0

    init(name: String, count: Int = 1) {
        self.name = name
        self.count = count
    }
}

@Model
final class LanguageEntity {
    var code: String
    var count: Int = 0

    init(code: String, count: Int = 1) {
        self.code = code
        self.count = count
    }
}

extension Notification.Name {
    static let mediaStateChanged = Notification.Name("mediaStateChanged")
    static let tasteWeightsChanged = Notification.Name("tasteWeightsChanged")
}

@Model
final class MediaItem {
    @Attribute(.unique) var id: String
    var title: String
    var overview: String
    var posterURL: String?
    var backdropURL: String?
    var releaseDate: Date?
    var lastUpdated: Date?
    var lastInteractionDate: Date?
    var lastStateChangeDate: Date = Date()
    var dateAdded: Date = Date()
    
    var tasteValue: String = "None"
    var stateValue: String = "Wishlist"
    var typeValue: String = "Movie"

    @Relationship(deleteRule: .cascade, inverse: \MovieDetails.item) var movieDetails: MovieDetails?
    @Relationship(deleteRule: .cascade, inverse: \TVShowDetails.item) var tvShowDetails: TVShowDetails?

    var state: MediaState? {
        get { MediaState(rawValue: stateValue) }
        set { stateValue = newValue?.rawValue ?? "Wishlist" }
    }
    
    var type: MediaType? {
        get { MediaType(rawValue: typeValue) }
        set { typeValue = newValue?.rawValue ?? "Movie" }
    }

    var cachedGenres: [String] = []
    var cachedNetwork: String?
    var cachedNetworkLogoPath: String?
    var cachedLanguage: String?
    var cachedNextAiringDate: Date?
    var themeColorHex: String?
    
    var storedSmartBadgeLabel: String?
    var storedSmartBadgeIcon: String?
    var storedSmartBadgeIsSparkle: Bool = false
    var storedIsUpcoming: Bool = false
    var storedIsBingeDrop: Bool = false
    var storedNextEpisodeLabel: String?
    var storedWatchProgressLabel: String?
    var storedProgress: Double?
    var searchableText: String = ""

    init(id: String, title: String, overview: String, posterURL: String? = nil, backdropURL: String? = nil, releaseDate: Date? = nil, type: MediaType? = .movie) {
        self.id = id
        self.title = title
        self.overview = overview
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.releaseDate = releaseDate
        self.typeValue = type?.rawValue ?? "Movie"
        self.lastUpdated = Date()
        self.lastInteractionDate = Date()
        self.lastStateChangeDate = Date()
        self.dateAdded = Date()
        self.updateSearchableText()
    }

    var availableStates: [MediaState] { 
        if type == .movie { return MediaState.allCases }
        
        let progress = storedProgress ?? 0
        if progress >= 1.0 {
            return [.completed, .rewatching]
        } else if progress > 0 {
            return [.active, .onHold, .dropped, .rewatching, .completed]
        }
        return MediaState.allCases
    }

    var isUpcoming: Bool {
        guard let date = cachedNextAiringDate else { return false }
        return date > Date()
    }
    
    var calculateIsUpcoming: Bool { isUpcoming }

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
    var watchProgressLabel: String? { storedWatchProgressLabel }
    var nextEpisodeToWatchLabel: String? { storedNextEpisodeLabel }
    var nextAiringDate: Date? { cachedNextAiringDate }

    var requiresMaintenanceRefresh: Bool {
        guard let last = lastUpdated else { return true }
        return Date().timeIntervalSince(last) > (30 * 86400)
    }

    func checkOverallCompletion() {
        if type == .tvShow, let details = tvShowDetails {
            let allEpisodes = details.seasons.filter { $0.seasonNumber > 0 }.flatMap { $0.episodes }
            if allEpisodes.isEmpty { return }
            
            let watchedCount = allEpisodes.filter { $0.isWatched }.count
            let progress = Double(watchedCount) / Double(allEpisodes.count)
            let currentState = state ?? .wishlist
            let now = Date()
            
            if progress >= 1.0 && currentState != .completed && currentState != .rewatching {
                self.state = .completed
                self.lastStateChangeDate = now
            } else if progress > 0 && progress < 1.0 && (currentState == .wishlist || currentState == .completed) {
                self.state = .active
                self.lastStateChangeDate = now
            } else if progress == 0 && (currentState == .active || currentState == .completed) {
                self.state = .wishlist
                self.lastStateChangeDate = now
            }
        }
    }
    
    func updateSearchableText() {
        var text = "\(title) \(overview)"
        if let movie = movieDetails {
            text += " \(movie.genres.joined(separator: " ")) \(movie.creators.joined(separator: " ")) \(movie.cast.map { $0.name }.joined(separator: " "))"
        } else if let tv = tvShowDetails {
            text += " \(tv.genres.joined(separator: " ")) \(tv.creators.joined(separator: " ")) \(tv.cast.map { $0.name }.joined(separator: " ")) \(tv.network ?? "")"
        }
        self.searchableText = text.lowercased()
    }

    func syncCachedProperties() {
        let now = Date()
        let currentState = state ?? .wishlist
        
        if type == .movie, let movie = movieDetails {
            self.cachedGenres = movie.genres
            self.cachedLanguage = movie.originalLanguage
            self.cachedNextAiringDate = self.releaseDate
        } else if type == .tvShow, let tv = tvShowDetails {
            self.cachedGenres = tv.genres
            self.cachedLanguage = tv.originalLanguage
            self.cachedNetwork = tv.network
            self.cachedNetworkLogoPath = tv.networkLogoPath
            
            // Recalculate episode stats - EXCLUDE SEASON 0 (Specials)
            let allEpisodes = tv.seasons.filter { $0.seasonNumber > 0 }.flatMap { $0.episodes }.sorted { e1, e2 in
                if e1.seasonNumber != e2.seasonNumber { return e1.seasonNumber < e2.seasonNumber }
                return e1.episodeNumber < e2.episodeNumber
            }
            let watched = allEpisodes.filter { $0.isWatched }
            
            // AUTOMATION: State Transitions based on progress
            if !allEpisodes.isEmpty {
                let progress = Double(watched.count) / Double(allEpisodes.count)
                
                if progress >= 1.0 && currentState != .completed && currentState != .rewatching {
                    self.state = .completed
                    self.lastStateChangeDate = now
                } else if progress > 0 && progress < 1.0 && (currentState == .wishlist || currentState == .completed) {
                    self.state = .active
                    self.lastStateChangeDate = now
                } else if progress == 0 && (currentState == .active || currentState == .completed) {
                    self.state = .wishlist
                    self.lastStateChangeDate = now
                }
            }
            
            // 1. Binge-Drop Detection (All remaining episodes of the current season released on same day)
            let unwatched = allEpisodes.filter { !$0.isWatched }
            if let firstUnwatched = unwatched.first {
                let currentSNum = firstUnwatched.seasonNumber
                let seasonUnwatched = unwatched.filter { $0.seasonNumber == currentSNum }
                
                if seasonUnwatched.count > 1 {
                    let firstDate = seasonUnwatched[0].airDate
                    let isSameDate = seasonUnwatched.allSatisfy { $0.airDate == firstDate && $0.airDate != nil }
                    let airDateAsDate = seasonUnwatched[0].airDateAsDate
                    
                    if isSameDate, let date = airDateAsDate {
                        let daysSinceRelease = now.timeIntervalSince(date) / 86400
                        // Binge drop if released in the past 5 days (and <= now)
                        if daysSinceRelease >= 0 && daysSinceRelease <= 5 {
                            self.storedIsBingeDrop = true
                        } else {
                            self.storedIsBingeDrop = false
                        }
                    } else {
                        self.storedIsBingeDrop = false
                    }
                } else {
                    self.storedIsBingeDrop = false
                }
            } else {
                self.storedIsBingeDrop = false
            }

            if !allEpisodes.isEmpty {
                self.storedProgress = Double(watched.count) / Double(allEpisodes.count)
                self.storedWatchProgressLabel = "\(watched.count)/\(allEpisodes.count) EP"
                
                if let next = unwatched.first {
                    self.storedNextEpisodeLabel = "S\(next.seasonNumber) E\(next.episodeNumber)"
                    self.cachedNextAiringDate = next.airDateAsDate ?? tv.nextEpisodeDate
                    
                    // Strictly require valid air date for availability-based badges
                    let isAvailable = (next.airDateAsDate != nil) && (next.airDateAsDate! <= now)

                    // Priority 1: Binge Drop (High Value Milestone)
                    if self.storedIsBingeDrop {
                        self.storedSmartBadgeLabel = "BINGE DROP"
                        self.storedSmartBadgeIcon = "sparkles.tv"
                        self.storedSmartBadgeIsSparkle = true
                    } 
                    // Priority 2: Finale (End of the road) - Also require air date for certainty
                    else if isAvailable, let season = next.season, next.episodeNumber == season.episodeCount {
                        self.storedSmartBadgeLabel = "FINALE"
                        self.storedSmartBadgeIcon = "flag.checkered"
                        self.storedSmartBadgeIsSparkle = true
                    } 
                    // Priority 3: Binge (For multi-season Liked/Loved/Watchlist with >= 30% progress)
                    else if isAvailable && (tv.numberOfSeasons ?? 0) > 1 && 
                            (tasteValue == "Like" || tasteValue == "Love" || currentState == .wishlist) &&
                            (self.storedProgress ?? 0) >= 0.3 {
                        self.storedSmartBadgeLabel = "BINGE"
                        self.storedSmartBadgeIcon = "sparkles.tv"
                        self.storedSmartBadgeIsSparkle = false
                    } else {
                        self.storedSmartBadgeLabel = nil
                    }
                } else {
                    // All currently known episodes watched
                    self.storedNextEpisodeLabel = nil
                    self.cachedNextAiringDate = tv.nextEpisodeDate
                    self.storedSmartBadgeLabel = nil
                }
            } else {
                // No episodes loaded yet OR only Season 0 episodes exist
                self.storedProgress = 0
                self.storedWatchProgressLabel = nil
                self.storedNextEpisodeLabel = nil
                self.cachedNextAiringDate = tv.nextEpisodeDate
                // No BINGE badge for 0 progress
                self.storedSmartBadgeLabel = nil
            }
        }
        
        // 2. Final Badge Overrides & Logic (Only if not already set by Finale/Binge Drop)
        if self.storedSmartBadgeLabel == nil {
            let isEnded = tvShowDetails?.status?.lowercased().contains("ended") ?? false || tvShowDetails?.status?.lowercased().contains("canceled") ?? false
            
            if let airDate = cachedNextAiringDate, 
               airDate <= now && airDate > now.addingTimeInterval(-86400 * 2), // Last 48 hours
               currentState != .completed,
               !isEnded {
                 self.storedSmartBadgeLabel = "STREAMING"
                 self.storedSmartBadgeIcon = "play.fill"
                 self.storedSmartBadgeIsSparkle = true
            } else if let release = releaseDate, 
                      release <= now && release > now.addingTimeInterval(-86400 * 7) { // Last 7 days
                self.storedSmartBadgeLabel = "NEW"
                self.storedSmartBadgeIcon = "sparkles"
                self.storedSmartBadgeIsSparkle = true
            }
        }

        self.storedIsUpcoming = isUpcoming
        updateSearchableText()
    }
}

@Model
final class MovieDetails {
    var tmdbID: Int
    var runtime: Int?
    var genres: [String] = []
    var voteAverage: Double?
    var originalLanguage: String?
    var creators: [String] = []
    @Relationship(deleteRule: .cascade, inverse: \CastMember.movieDetails) var cast: [CastMember] = []
    var item: MediaItem?

    init(tmdbID: Int) {
        self.tmdbID = tmdbID
    }
}

@Model
final class TVShowDetails {
    var tmdbID: Int
    var tvMazeID: Int?
    var numberOfSeasons: Int?
    var numberOfEpisodes: Int?
    var status: String?
    var voteAverage: Double?
    var genres: [String] = []
    var network: String?
    var networkLogoPath: String?
    var originalLanguage: String?
    var creators: [String] = []
    var timezone: String?
    var nextEpisodeDate: Date?
    var nextEpisodeNumber: Int?
    var nextSeasonNumber: Int?
    var nextEpisodeTime: String?

    @Relationship(deleteRule: .cascade, inverse: \TVSeason.tvShowDetails) var seasons: [TVSeason] = []
    @Relationship(deleteRule: .cascade, inverse: \CastMember.tvShowDetails) var cast: [CastMember] = []
    var item: MediaItem?

    init(tmdbID: Int) {
        self.tmdbID = tmdbID
    }
    
    func recalculateCachedProperties(triggerSync: Bool = true) {
        if triggerSync { item?.syncCachedProperties() }
    }
}

@Model
final class CastMember {
    var name: String
    var characterName: String
    var profileURL: String?
    var order: Int
    var movieDetails: MovieDetails?
    var tvShowDetails: TVShowDetails?

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
    var showID: Int?
    var uniqueID: String?
    var tvShowDetails: TVShowDetails?
    @Relationship(deleteRule: .cascade, inverse: \TVEpisode.season) var episodes: [TVEpisode] = []

    init(seasonNumber: Int, name: String, episodeCount: Int, airDate: String? = nil, showID: Int? = nil) {
        self.seasonNumber = seasonNumber
        self.name = name
        self.episodeCount = episodeCount
        self.airDate = airDate
        self.showID = showID
        if let showID = showID { self.uniqueID = "\(showID)_\(seasonNumber)" }
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
    var uniqueID: String? = nil
    var season: TVSeason?
    
    var airDateAsDate: Date? {
        DateUtils.parseEpisodeDate(airDate, time: nil, airstamp: airstamp, timezone: season?.tvShowDetails?.timezone, serviceName: season?.tvShowDetails?.network, for: season?.tvShowDetails)
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
        if let showID = showID {
            self.uniqueID = "\(showID)_\(seasonNumber)_\(episodeNumber)"
        } else {
            self.uniqueID = UUID().uuidString
        }
    }
}

@Model
final class PersonImageEntity {
    var name: String
    var profileURL: String?
    
    init(name: String, profileURL: String?) {
        self.name = name
        self.profileURL = profileURL
    }
}
