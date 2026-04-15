import Foundation
import SwiftData

enum MediaState: String, Codable, CaseIterable {
    case wishlist = "Wishlist"
    case active = "Active"
    case completed = "Completed"
    
    var displayName: String {
        switch self {
        case .wishlist: return "Waitlist"
        case .active: return "In Progress"
        case .completed: return "Completed"
        }
    }
}

enum MediaType: String, Codable, CaseIterable {
    case movie = "Movie"
    case tvShow = "TV Show"
    case book = "Book"
    
    var pluralName: String {
        switch self {
        case .movie: return "Movies"
        case .tvShow: return "TV Shows"
        case .book: return "Books"
        }
    }
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
    
    // Type-specific data
    var movieDetails: MovieDetails?
    var tvShowDetails: TVShowDetails?
    var bookDetails: BookDetails?
    
    var nextAiringDate: Date? {
        let currentType = type ?? .movie
        if currentType == .movie {
            return releaseDate
        } else if currentType == .tvShow {
            // Priority: The oldest episode you haven't watched yet.
            // Even if it aired last week, it stays in the header as 'Available Now'
            return tvShowDetails?.oldestUnwatchedEpisodeAirDate ?? tvShowDetails?.nextEpisodeDate
        }
        return nil
    }
    
    /// The absolute next episode to air in the future (regardless of watch history)
    var absoluteNextAiringDate: Date? {
        if type == .tvShow {
            return tvShowDetails?.nextEpisodeDate
        }
        return releaseDate
    }
    
    var isRecentlyReleased: Bool {
        let currentType = type ?? .movie
        
        // Use releaseDate for movies or nextEpisodeDate for TV as the source of truth for "Recently"
        let dateToCheck: Date?
        if currentType == .tvShow {
            // Check if there's a confirmed episode that aired within the last 5 days
            // We use the oldestUnwatchedEpisodeAirDate here because it's the best indicator 
            // that the user has something new to watch right now.
            dateToCheck = tvShowDetails?.oldestUnwatchedEpisodeAirDate
        } else {
            dateToCheck = releaseDate
        }

        guard let date = dateToCheck else { return false }
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()
        return date <= Date() && date >= fiveDaysAgo
    }
    
    var isUpcoming: Bool {
        // 1. Check if there's a confirmed future release date
        if let nextDate = nextAiringDate, nextDate > Date() {
            return true
        }
        
        // 2. Check if it was released within the last 5 days (Available Now buffer)
        return isRecentlyReleased
    }
    
    var isActive: Bool {
        let currentType = type ?? .movie
        let currentState = state ?? .wishlist
        
        if currentType == .tvShow, let tv = tvShowDetails {
            let allEpisodes = tv.seasons.flatMap { $0.episodes }
            let watchedCount = allEpisodes.filter { $0.isWatched }.count
            let totalCount = tv.numberOfEpisodes ?? 0
            
            // It's active if you've seen at least one, but not all
            return watchedCount > 0 && watchedCount < totalCount
        } else if currentType == .book {
            // For now, books are 'active' if their state is set to active
            return currentState == .active
        } else if currentType == .movie {
            return currentState == .active
        }
        return false
    }
    
    var genres: [String] {
        if let movie = movieDetails {
            return movie.genres
        } else if tvShowDetails != nil {
            // TMDB TV details don't store genres directly in our model yet, 
            // but we can add it or derive it. For now, we use existing fields.
            return []
        } else if let book = bookDetails {
            return book.authors
        }
        return []
    }

    var nextAiringLabel: String? {
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
                return "Next: \(formatter.string(from: date))"
            }
        }
        
        return isRecentlyReleased ? "Available Now" : nil
    }

    var watchProgressLabel: String? {
        if type == .tvShow, let tv = tvShowDetails {
            let watched = tv.seasons.reduce(0) { $0 + $1.episodes.filter { $0.isWatched }.count }
            let total = tv.numberOfEpisodes ?? 0
            return "\(watched)/\(total)"
        }
        return state?.displayName
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
}

@Model
final class MovieDetails {
    var tmdbID: Int
    var runtime: Int?
    var genres: [String]
    var voteAverage: Double?
    @Relationship(deleteRule: .cascade) var cast: [CastMember] = []
    
    init(tmdbID: Int, runtime: Int? = nil, genres: [String] = [], voteAverage: Double? = nil) {
        self.tmdbID = tmdbID
        self.runtime = runtime
        self.genres = genres
        self.voteAverage = voteAverage
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
    var timezone: String?
    var numberOfSeasons: Int?
    var numberOfEpisodes: Int?
    var voteAverage: Double?
    
    @Relationship(deleteRule: .cascade) var seasons: [TVSeason] = []
    @Relationship(deleteRule: .cascade) var cast: [CastMember] = []
    
    var oldestUnwatchedEpisodeAirDate: Date? {
        let allEpisodes = seasons.flatMap { $0.episodes }
        let unwatched = allEpisodes.filter { !$0.isWatched }
        
        let dates = unwatched.compactMap { $0.airDateAsDate }
        return dates.min()
    }
    
    init(tmdbID: Int, tvdbID: Int? = nil, tvMazeID: Int? = nil, nextEpisodeDate: Date? = nil, nextEpisodeTime: String? = nil, nextEpisodeName: String? = nil, nextEpisodeNumber: Int? = nil, nextSeasonNumber: Int? = nil, status: String? = nil, network: String? = nil, timezone: String? = nil, numberOfSeasons: Int? = nil, numberOfEpisodes: Int? = nil, voteAverage: Double? = nil) {
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
        self.timezone = timezone
        self.numberOfSeasons = numberOfSeasons
        self.numberOfEpisodes = numberOfEpisodes
        self.voteAverage = voteAverage
    }
}

@Model
final class CastMember {
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

@Model
final class BookDetails {
    var googleBooksID: String
    var authors: [String]
    var pageCount: Int?
    var isbn: String?
    
    init(googleBooksID: String, authors: [String] = [], pageCount: Int? = nil, isbn: String? = nil) {
        self.googleBooksID = googleBooksID
        self.authors = authors
        self.pageCount = pageCount
        self.isbn = isbn
    }
}
