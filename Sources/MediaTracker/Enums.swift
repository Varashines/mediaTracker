import Foundation
import SwiftUI

enum AppError: Error {
    case generic(String)
}

enum NavigationCategory: String, CaseIterable, Identifiable, Sendable {
    case home = "Home"
    case upcoming = "Upcoming"
    case inProgress = "InProgress"
    case watchlist = "Watchlist"
    case all = "All"
    case loved = "Loved"
    case completed = "Completed"
    case archive = "Archive"
    case disliked = "Disliked"
    case binge = "Binge"
    case discover = "Discover"
    case insights = "Insights"
    case movie = "Movie"
    case tvShow = "TV Show"
    case smartHub = "Smart Hub"
    case quickBites = "Quick Bites"
    case catchUp = "Catch Up"
    case stalled = "Stalled"
    case releaseRadar = "Release Radar"

    var id: String { self.rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .upcoming: return "Release Calendar"
        case .inProgress: return "In Progress"
        case .watchlist: return "Watchlist"
        case .all: return "Library"
        case .loved: return "Loved"
        case .completed: return "Completed"
        case .archive: return "Re-watching"
        case .disliked: return "Disliked"
        case .binge: return "Binge"
        case .discover: return "Discovery Hub"
        case .insights: return "Statistics"
        case .movie: return "Movies"
        case .tvShow: return "TV Shows"
        case .smartHub: return "Smart Hub"
        case .quickBites: return "Quick Bites"
        case .catchUp: return "Catch Up"
        case .stalled: return "On Hold"
        case .releaseRadar: return "Release Radar"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house"
        case .upcoming: return "calendar.badge.clock" // Matches the visual style shown or standard
        case .inProgress: return "play.circle"
        case .watchlist: return "list.bullet.rectangle"
        case .all: return "tray.full"
        case .loved: return "heart"
        case .completed: return "checkmark.circle"
        case .archive: return "arrow.clockwise"
        case .disliked: return "hand.thumbsdown"
        case .binge: return "rectangle.stack"
        case .discover: return "sparkles.tv"
        case .insights: return "chart.bar"
        case .movie: return "film"
        case .tvShow: return "tv"
        case .smartHub: return "sparkles.rectangle.stack"
        case .quickBites: return "timer"
        case .catchUp: return "arrow.uturn.right.circle"
        case .stalled: return "pause.circle"
        case .releaseRadar: return "sparkles"
        }
    }
}

enum SidebarItem: Hashable, Sendable {
    case category(NavigationCategory)
    case collection(UUID, name: String, icon: String)

    var id: String {
        switch self {
        case .category(let cat): return cat.rawValue
        case .collection(let id, _, _): return id.uuidString
        }
    }
}

enum MediaState: String, Codable, CaseIterable, Sendable {
    case wishlist = "Wishlist"
    case active = "Active"
    case onHold = "On Hold"
    case dropped = "Dropped"
    case rewatching = "Re-watching"
    case completed = "Completed"

    var displayName: String {
        switch self {
        case .wishlist: return String(localized: "Watchlist")
        case .active: return String(localized: "In Progress")
        case .onHold: return String(localized: "On Hold")
        case .dropped: return String(localized: "Dropped")
        case .rewatching: return String(localized: "Re-watching")
        case .completed: return String(localized: "Completed")
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

enum MediaType: String, Codable, CaseIterable, Sendable {
    case movie = "Movie"
    case tvShow = "TV Show"

    var pluralName: String {
        switch self {
        case .movie: return String(localized: "Movies")
        case .tvShow: return String(localized: "TV Shows")
        }
    }
}

enum FilterType: String, Codable, Hashable, Sendable {
    case genre = "Genre"
    case studio = "Studio"
    case language = "Language"
}

enum TasteValue: String, Codable, CaseIterable, Sendable {
    case none = "None"
    case like = "Like"
    case love = "Love"
    case dislike = "Dislike"

    var iconName: String {
        switch self {
        case .none: return "circle"
        case .like: return "hand.thumbsup.fill"
        case .love: return "heart.fill"
        case .dislike: return "hand.thumbsdown.fill"
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case alphabetical = "Alphabetical"
    case newestRelease = "Newest Release"
    case recentlyAdded = "Recently Added"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .newestRelease: return "calendar"
        case .recentlyAdded: return "clock.badge.checkmark"
        }
    }
}

enum GroupBy: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case genre = "Genre"
    case language = "Language"
    case network = "Network"
    case year = "Year"
    case category = "Category"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .none: return "square.grid.2x2"
        case .genre: return "tag"
        case .language: return "globe"
        case .network: return "tv"
        case .year: return "calendar.badge.clock"
        case .category: return "folder"
        }
    }
}
