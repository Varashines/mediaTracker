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
    case ocean = "Ocean"
    case berry = "Berry"
    case minty = "Minty"
    case emerald = "Emerald"
    case candy = "Candy"
    case lava = "Lava"

    var id: String { self.rawValue }

    var color: Color {
        switch self {
        case .cosmic: return Color(red: 0.55, green: 0.35, blue: 0.95)
        case .solar: return Color(red: 1.00, green: 0.45, blue: 0.20)
        case .ocean: return Color(red: 0.10, green: 0.45, blue: 0.90) // Darker blue
        case .berry: return Color(red: 0.85, green: 0.15, blue: 0.45)
        case .minty: return Color(red: 0.00, green: 0.80, blue: 0.60)
        case .emerald: return Color(red: 0.15, green: 0.65, blue: 0.35) // Deep green
        case .candy: return Color(red: 1.00, green: 0.40, blue: 0.70)
        case .lava: return Color(red: 1.00, green: 0.20, blue: 0.30)
        }
    }

    func brandBackground(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark {
            switch self {
            case .cosmic: return Color(red: 0.12, green: 0.08, blue: 0.25)
            case .solar: return Color(red: 0.25, green: 0.12, blue: 0.08)
            case .ocean: return Color(red: 0.05, green: 0.15, blue: 0.28)
            case .berry: return Color(red: 0.22, green: 0.08, blue: 0.16)
            case .minty: return Color(red: 0.08, green: 0.22, blue: 0.18)
            case .emerald: return Color(red: 0.05, green: 0.22, blue: 0.10)
            case .candy: return Color(red: 0.24, green: 0.10, blue: 0.18)
            case .lava: return Color(red: 0.25, green: 0.08, blue: 0.10)
            }
        } else {
            switch self {
            case .cosmic: return Color(red: 0.97, green: 0.96, blue: 1.0)
            case .solar: return Color(red: 1.0, green: 0.98, blue: 0.96)
            case .ocean: return Color(red: 0.95, green: 0.98, blue: 1.0)
            case .berry: return Color(red: 1.0, green: 0.96, blue: 0.98)
            case .minty: return Color(red: 0.96, green: 1.0, blue: 0.98)
            case .emerald: return Color(red: 0.96, green: 1.0, blue: 0.96)
            case .candy: return Color(red: 1.0, green: 0.96, blue: 0.99)
            case .lava: return Color(red: 1.0, green: 0.96, blue: 0.96)
            }
        }
    }
}

struct DiscoveryFilter: Hashable, Codable {
    let type: FilterType
    let name: String
    var sourceNames: [String]? = nil
}

struct SimpleCastMember: Codable, Identifiable {
    let id: String
    let name: String
    let characterName: String
    let profileURL: String?
    let order: Int
}

struct DiscoveryNode: Identifiable, Equatable, Codable {
    var id: String { code ?? name }
    let name: String
    var code: String? = nil
    let logoPath: String?
    let count: Int
    var themeColorHex: String? = nil
    var sourceNames: [String]? = nil
}

@Model
final class NetworkEntity {
    var name: String
    var logoPath: String?
    var count: Int = 0
    var themeColorHex: String?
    var sourceNamesData: Data? = nil

    var sourceNames: [String]? {
        get {
            guard let data = sourceNamesData else { return nil }
            return try? JSONDecoder().decode([String].self, from: data)
        }
        set {
            sourceNamesData = try? JSONEncoder().encode(newValue)
        }
    }

    init(name: String, logoPath: String?, count: Int = 1, sourceNames: [String]? = nil) {
        self.name = name
        self.logoPath = logoPath
        self.count = count
        self.sourceNames = sourceNames
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
    static let mediaItemRefreshed = Notification.Name("mediaItemRefreshed")
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
    var remainingEpisodesCount: Int?
    
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

    var displayCast: [SimpleCastMember] {
        if let movie = movieDetails, !movie.cast.isEmpty {
            return movie.cast.map { SimpleCastMember(id: $0.uniqueID ?? UUID().uuidString, name: $0.name, characterName: $0.characterName, profileURL: $0.profileURL, order: $0.order) }
        } else if let tv = tvShowDetails, !tv.cast.isEmpty {
            return tv.cast.map { SimpleCastMember(id: $0.uniqueID ?? UUID().uuidString, name: $0.name, characterName: $0.characterName, profileURL: $0.profileURL, order: $0.order) }
        }
        return []
    }

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

    static func availableStates(for type: MediaType, progress: Double?) -> [MediaState] {
        if type == .movie { return MediaState.allCases }
        
        let progressVal = progress ?? 0
        if progressVal >= 1.0 {
            return [.completed, .rewatching]
        } else if progressVal > 0 {
            return [.active, .onHold, .dropped, .rewatching, .completed]
        }
        return MediaState.allCases
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
}

// MARK: - MediaItem Business Logic
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

            let relevantSeasons = tv.seasons.filter { $0.seasonNumber > 0 }
            let allEpisodes = relevantSeasons.flatMap { $0.episodes }

            if allEpisodes.isEmpty {
                self.storedProgress = 0
                self.storedWatchProgressLabel = nil
                self.storedNextEpisodeLabel = nil
                self.cachedNextAiringDate = tv.nextEpisodeDate
                self.storedSmartBadgeLabel = nil
                self.remainingEpisodesCount = 0
                tv.remainingEpisodesCount = 0
                return
            }

            let watched = allEpisodes.filter { $0.isWatched }
            let aired = allEpisodes.filter { ($0.airDateAsDate ?? .distantFuture) <= now }
            let remaining = aired.count - watched.count
            self.remainingEpisodesCount = max(0, remaining)
            tv.remainingEpisodesCount = max(0, remaining)

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

            self.storedProgress = progress
            self.storedWatchProgressLabel = "\(watched.count)/\(allEpisodes.count) EP"

            let unwatched = allEpisodes.filter { !$0.isWatched }.sorted { e1, e2 in
                if e1.seasonNumber != e2.seasonNumber { return e1.seasonNumber < e2.seasonNumber }
                return e1.episodeNumber < e2.episodeNumber
            }

            if let firstUnwatched = unwatched.first {
                self.storedNextEpisodeLabel = "S\(firstUnwatched.seasonNumber) E\(firstUnwatched.episodeNumber)"
                self.cachedNextAiringDate = firstUnwatched.airDateAsDate ?? tv.nextEpisodeDate

                let currentSNum = firstUnwatched.seasonNumber
                let seasonUnwatched = unwatched.filter { $0.seasonNumber == currentSNum }

                if seasonUnwatched.count > 1 {
                    let firstDate = seasonUnwatched[0].airDate
                    let isSameDate = seasonUnwatched.allSatisfy { $0.airDate == firstDate && $0.airDate != nil }
                    let airDateAsDate = seasonUnwatched[0].airDateAsDate

                    if isSameDate, let date = airDateAsDate {
                        let daysDiff = date.timeIntervalSince(now) / 86400
                        // Binge drop if within 5 days in past OR next 7 days in future
                        self.storedIsBingeDrop = (daysDiff >= -5 && daysDiff <= 7)
                    } else {
                        self.storedIsBingeDrop = false
                    }
                } else {
                    self.storedIsBingeDrop = false
                }

                let airDate = firstUnwatched.airDateAsDate
                let isAvailable = (airDate != nil) && (airDate! <= now)
                let isUpcomingSoon = (airDate != nil) && (airDate! > now && airDate! <= now.addingTimeInterval(86400 * 2))
                let isRecentlyAired = isAvailable && airDate! > now.addingTimeInterval(-86400 * 2)
                let isPremiereDateValid = (airDate != nil) && (Calendar.current.isDateInToday(airDate!) || airDate! > now)

                // PECKING ORDER START
                if firstUnwatched.episodeNumber == 1 && isPremiereDateValid {
                    if firstUnwatched.seasonNumber == 1 {
                        self.storedSmartBadgeLabel = "SERIES PREMIERE"
                        self.storedSmartBadgeIcon = "star.square.fill"
                    } else {
                        self.storedSmartBadgeLabel = "SEASON PREMIERE"
                        self.storedSmartBadgeIcon = "play.square.stack.fill"
                    }
                    self.storedSmartBadgeIsSparkle = true
                } else if self.storedIsBingeDrop {
                    self.storedSmartBadgeLabel = "BINGE DROP"
                    self.storedSmartBadgeIcon = "sparkles.tv"
                    self.storedSmartBadgeIsSparkle = true
                } else if let season = firstUnwatched.season, firstUnwatched.episodeNumber == season.episodeCount {
                    self.storedSmartBadgeLabel = "FINALE"
                    self.storedSmartBadgeIcon = "flag.checkered"
                    self.storedSmartBadgeIsSparkle = true
                } else if isUpcomingSoon {
                    self.storedSmartBadgeLabel = "SOON"
                    self.storedSmartBadgeIcon = "clock.badge.fill"
                    self.storedSmartBadgeIsSparkle = true
                } else if isRecentlyAired {
                    self.storedSmartBadgeLabel = "STREAMING"
                    self.storedSmartBadgeIcon = "play.fill"
                    self.storedSmartBadgeIsSparkle = true
                } else if isAvailable && (tv.numberOfSeasons ?? 0) >= 1 && 
                        (tasteValue == "Like" || tasteValue == "Love" || currentState == .wishlist) &&
                        progress >= 0.3 && (self.remainingEpisodesCount ?? 0) > 1 {
                    self.storedSmartBadgeLabel = "BINGE"
                    self.storedSmartBadgeIcon = "sparkles.tv"
                    self.storedSmartBadgeIsSparkle = false
                } else {
                    self.storedSmartBadgeLabel = nil
                }
                // PECKING ORDER END
            } else {
                self.storedNextEpisodeLabel = nil
                self.cachedNextAiringDate = tv.nextEpisodeDate
                self.storedSmartBadgeLabel = nil
                self.storedIsBingeDrop = false
            }
        }

        if self.storedSmartBadgeLabel == nil {
            let isEnded = tvShowDetails?.status?.lowercased().contains("ended") ?? false || tvShowDetails?.status?.lowercased().contains("canceled") ?? false

            if let airDate = cachedNextAiringDate {
                if airDate > now && airDate <= now.addingTimeInterval(86400 * 2) {
                    self.storedSmartBadgeLabel = "SOON"
                    self.storedSmartBadgeIcon = "clock.badge.fill"
                    self.storedSmartBadgeIsSparkle = true
                } else if airDate <= now && airDate > now.addingTimeInterval(-86400 * 2) && !isEnded {
                    self.storedSmartBadgeLabel = "STREAMING"
                    self.storedSmartBadgeIcon = "play.fill"
                    self.storedSmartBadgeIsSparkle = true
                }
            }
            
            if self.storedSmartBadgeLabel == nil, let release = releaseDate {
                if release > now && release <= now.addingTimeInterval(86400 * 2) {
                    self.storedSmartBadgeLabel = "SOON"
                    self.storedSmartBadgeIcon = "clock.badge.fill"
                    self.storedSmartBadgeIsSparkle = true
                } else if release <= now && release > now.addingTimeInterval(-86400 * 7) {
                    self.storedSmartBadgeLabel = "NEW"
                    self.storedSmartBadgeIcon = "sparkles"
                    self.storedSmartBadgeIsSparkle = true
                }
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
    var remainingEpisodesCount: Int?
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
    var uniqueID: String?
    var name: String
    var characterName: String
    var profileURL: String?
    var order: Int
    var movieDetails: MovieDetails?
    var tvShowDetails: TVShowDetails?

    init(name: String, characterName: String, profileURL: String? = nil, order: Int = 0, mediaID: String? = nil) {
        self.name = name
        self.characterName = characterName
        self.profileURL = profileURL
        self.order = order
        if let mID = mediaID {
            self.uniqueID = "\(mID)_\(name)"
        } else {
            self.uniqueID = UUID().uuidString
        }
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
    var showID: Int?
    var uniqueID: String? = nil
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

@Model
final class PersonImageEntity {
    var name: String
    var profileURL: String?
    
    init(name: String, profileURL: String?) {
        self.name = name
        self.profileURL = profileURL
    }
}
