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
    case releaseRadar = "Release Radar"
    case smartUpcoming = "Smart Upcoming"
    case onThisDay = "On This Day"

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
        case .archive: return "Shelved"
        case .disliked: return "Disliked"
        case .binge: return "Binge"
        case .discover: return "Discovery Hub"
        case .insights: return "Snapshot"
        case .movie: return "Movies"
        case .tvShow: return "TV Shows"
        case .smartHub: return "Smart Hub"
        case .quickBites: return "Quick Bites"
        case .catchUp: return "Catch Up"
        case .releaseRadar: return "Release Radar"
        case .smartUpcoming: return "Premiere Radar"
        case .onThisDay: return "On This Day"
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
        case .archive: return "archivebox"
        case .disliked: return "hand.thumbsdown"
        case .binge: return "rectangle.stack"
        case .discover: return "sparkles.tv"
        case .insights: return "chart.bar"
        case .movie: return "film"
        case .tvShow: return "tv"
        case .smartHub: return "sparkles.rectangle.stack"
        case .quickBites: return "timer"
        case .catchUp: return "arrow.uturn.right.circle"
        case .releaseRadar: return "sparkles"
        case .smartUpcoming: return "calendar.badge.clock"
        case .onThisDay: return "calendar.badge.clock"
        }
    }

    var isSmartCategory: Bool {
        switch self {
        case .releaseRadar, .smartUpcoming, .catchUp, .loved, .binge, .quickBites, .archive, .onThisDay:
            return true
        default:
            return false
        }
    }

    var moodColor: Color {
        switch self {
        case .home: return .clear
        case .discover: return Color(hex: "8B5CF6") ?? .purple
        case .upcoming, .releaseRadar, .smartUpcoming: return Color(hex: "F97316") ?? .orange
        case .all: return .clear
        case .movie: return Color(hex: "6366F1") ?? .indigo
        case .tvShow: return Color(hex: "14B8A6") ?? .teal
        case .smartHub: return Color(hex: "8B5CF6") ?? .purple
        case .insights: return Color(hex: "6B7280") ?? .gray
        case .inProgress: return Color(hex: "22C55E") ?? .green
        case .watchlist: return Color(hex: "EAB308") ?? .yellow
        case .loved: return Color(hex: "EC4899") ?? .pink
        case .completed: return Color(hex: "22C55E") ?? .green
        case .archive: return Color(hex: "78716C") ?? .brown
        case .disliked: return Color(hex: "EF4444") ?? .red
        case .binge: return Color(hex: "F97316") ?? .orange
        case .quickBites: return Color(hex: "A855F7") ?? .purple
        case .catchUp: return Color(hex: "3B82F6") ?? .blue
        case .onThisDay: return Color(hex: "F59E0B") ?? .orange
        }
    }
}

enum SidebarItem: Hashable, Sendable {
    case category(NavigationCategory)
    case collection(UUID, name: String, icon: String)
    case yearReview

    var id: String {
        switch self {
        case .category(let cat): return cat.rawValue
        case .collection(let id, _, _): return id.uuidString
        case .yearReview: return "yearReview"
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

    static let activeRaw = MediaState.active.rawValue
    static let completedRaw = MediaState.completed.rawValue
    static let wishlistRaw = MediaState.wishlist.rawValue
    static let onHoldRaw = MediaState.onHold.rawValue
    static let droppedRaw = MediaState.dropped.rawValue
    static let rewatchingRaw = MediaState.rewatching.rawValue

    var displayName: String {
        // We pass an English default to String(localized:) so the UI always renders
        // sensibly even on devices that don't ship a matching localization. We do
        // not ship a Localizable.xcstrings, so these calls are effectively a no-op
        // today; the pattern is in place to switch to key-based localization later
        // by replacing the defaults with key names.
        switch self {
        case .wishlist: return String(localized: "Watchlist", defaultValue: "Watchlist")
        case .active: return String(localized: "In Progress", defaultValue: "In Progress")
        case .onHold: return String(localized: "On Hold", defaultValue: "On Hold")
        case .dropped: return String(localized: "Dropped", defaultValue: "Dropped")
        case .rewatching: return String(localized: "Re-watching", defaultValue: "Re-watching")
        case .completed: return String(localized: "Completed", defaultValue: "Completed")
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

    var accentColor: Color {
        Self.accentColors[self] ?? Color.gray
    }

    /// Precomputed on/off foreground for the accent capsule (avoids per-cell NSColor work).
    var badgeForegroundColor: Color {
        Self.accentForegrounds[self] ?? .white
    }

    private static let accentColors: [MediaState: Color] = [
        .active: Color.fromOKLCH(l: 0.55, c: 0.2, h: 250),
        .rewatching: Color.fromOKLCH(l: 0.55, c: 0.2, h: 250),
        .wishlist: Color.fromOKLCH(l: 0.7, c: 0.18, h: 75),
        .onHold: Color.fromOKLCH(l: 0.5, c: 0.05, h: 250),
        .dropped: Color.fromOKLCH(l: 0.6, c: 0.15, h: 25),
        .completed: Color.fromOKLCH(l: 0.65, c: 0.2, h: 145)
    ]

    private static let accentForegrounds: [MediaState: Color] = accentColors.mapValues { $0.isLightColor ? .black : .white }
}

enum MediaType: String, Codable, CaseIterable, Sendable {
    case movie = "Movie"
    case tvShow = "TV Show"

    static let movieRaw = MediaType.movie.rawValue
    static let tvShowRaw = MediaType.tvShow.rawValue

    var pluralName: String {
        // See MediaState.displayName for the localization pattern note.
        switch self {
        case .movie: return String(localized: "Movies", defaultValue: "Movies")
        case .tvShow: return String(localized: "TV Shows", defaultValue: "TV Shows")
        }
    }
}

enum FilterType: String, Codable, Hashable, Sendable {
    case genre = "Genre"
    case studio = "Studio"
    case network = "Network"
    case language = "Language"
    case badge = "Badge"
    case provider = "Provider"
    case onThisDay = "On This Day"
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

    var color: Color {
        switch self {
        case .love: return .red
        case .like: return .blue
        case .dislike: return .gray
        case .none: return .secondary
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case alphabetical = "Alphabetical"
    case newestRelease = "Newest Release"
    case recentlyAdded = "Recently Added"
    case recentInteraction = "Recent Interaction"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .alphabetical: return "textformat.abc"
        case .newestRelease: return "calendar"
        case .recentlyAdded: return "clock.badge.checkmark"
        case .recentInteraction: return "clock.arrow.2.circlepath"
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
    case watchProvider = "Watch Provider"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .none: return "square.grid.2x2"
        case .genre: return "tag"
        case .language: return "globe"
        case .network: return "tv"
        case .year: return "calendar.badge.clock"
        case .category: return "folder"
        case .watchProvider: return "tv.and.mediabox"
        }
    }
}

// MARK: - Mood Sentiment

enum Mood: String, Codable, CaseIterable, Sendable {
    case cozy = "Cozy"
    case intense = "Intense"
    case mindBending = "Trippy"
    case epic = "Epic"
    case emotional = "Sad"
    case chill = "Chill"

    /// Unified 6-Vibe Taxonomy across Movies & TV Shows
    static func moods(for type: MediaType?) -> [Mood] {
        return [.cozy, .intense, .mindBending, .epic, .emotional, .chill]
    }

    var emoji: String {
        switch self {
        case .cozy: return "cloud.fill"
        case .intense: return "flame.fill"
        case .mindBending: return "infinity"
        case .epic: return "crown.fill"
        case .emotional: return "cloud.drizzle.fill"
        case .chill: return "popcorn.fill"
        }
    }

    var color: Color {
        switch self {
        case .cozy: return Color(red: 0.95, green: 0.60, blue: 0.20)         // Warm Amber
        case .intense: return Color(red: 0.92, green: 0.25, blue: 0.30)      // Crimson Red
        case .mindBending: return Color(red: 0.15, green: 0.70, blue: 0.85)  // Electric Cyan
        case .epic: return Color(red: 0.65, green: 0.40, blue: 0.95)         // Royal Violet
        case .emotional: return Color(red: 0.88, green: 0.35, blue: 0.55)    // Soft Rose Pink
        case .chill: return Color(red: 0.45, green: 0.75, blue: 0.50)        // Sage Emerald Green
        }
    }

    /// Map legacy/variant mood strings seamlessly to the 6 canonical vibes so zero user data is lost.
    static func normalized(_ value: String) -> Mood? {
        switch value {
        case "Warm", "Comfort", "Cozy", "Comfort Rewatch", "Rewatch": return .cozy
        case "Intense", "Tense", "Hype", "Hype ", "Wild", "Twisty", "Cliffhanger", "Thrilled": return .intense
        case "Mind-Bending", "Mind Bending", "Brain", "Slow Burn", "Slowburn", "Deep ": return .mindBending
        case "Epic", "Wowed", "Peak", "Peak TV", "Masterpiece", "MasterpieceRun", "Inspired", "Awe": return .epic
        case "Emotional", "Deep", "Heavy", "Moved": return .emotional
        case "Chill", "Vibey", "Fun", "Meh", "Binge", "Bingeable", "Weekly", "Guilty", "Guilty Pleasure", "Relaxed", "Calm", "Amused", "Joy", "Nothing", "Flat": return .chill
        default: return Mood(rawValue: value)
        }
    }
}
