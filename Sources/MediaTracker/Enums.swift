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
    case settings = "Settings"
    case collectionsHub = "Collections Hub"
    case smartCollections = "Smart Hub"
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
        case .archive: return "Archive"
        case .disliked: return "Disliked"
        case .binge: return "Binge"
        case .discover: return "Discovery Hub"
        case .insights: return "Statistics"
        case .movie: return "Movies"
        case .tvShow: return "TV Shows"
        case .settings: return "Settings"
        case .collectionsHub: return "My Collections"
        case .smartCollections: return "Smart Hub"
        case .quickBites: return "Quick Bites"
        case .catchUp: return "Catch Up Priority"
        case .stalled: return "Stalled / Stale"
        case .releaseRadar: return "Release Radar"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .upcoming: return "calendar"
        case .inProgress: return "play.circle"
        case .watchlist: return "list.bullet.rectangle"
        case .all: return "tray.full"
        case .loved: return "heart.fill"
        case .completed: return "checkmark.circle.fill"
        case .archive: return "archivebox"
        case .disliked: return "hand.thumbsdown.fill"
        case .binge: return "rectangle.stack.fill"
        case .discover: return "sparkles.tv"
        case .insights: return "chart.bar.fill"
        case .movie: return "film"
        case .tvShow: return "tv"
        case .settings: return "gearshape.fill"
        case .collectionsHub: return "folder.badge.plus"
        case .smartCollections: return "sparkles.rectangle.stack"
        case .quickBites: return "timer"
        case .catchUp: return "arrow.uturn.right.circle.fill"
        case .stalled: return "hourglass.bottomhalf.filled"
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

enum ThemeStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard = "Standard"
    case brand = "Brand Blue"
    var id: String { self.rawValue }
}

enum AppAccent: String, CaseIterable, Identifiable, Codable, Sendable {
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
    case kanban = "Collection Progress"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .none: return "square.grid.2x2"
        case .genre: return "tag"
        case .language: return "globe"
        case .network: return "tv"
        case .year: return "calendar.badge.clock"
        case .category: return "folder"
        case .kanban: return "checklist"
        }
    }
}
