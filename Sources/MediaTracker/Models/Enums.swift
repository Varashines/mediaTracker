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
        }
    }

    var isSmartCategory: Bool {
        switch self {
        case .releaseRadar, .smartUpcoming, .catchUp, .loved, .binge, .quickBites, .archive:
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
        switch self {
        case .active, .rewatching: return Color.fromOKLCH(l: 0.55, c: 0.2, h: 250)
        case .wishlist: return Color.fromOKLCH(l: 0.7, c: 0.18, h: 75)
        case .onHold: return Color.fromOKLCH(l: 0.5, c: 0.05, h: 250)
        case .dropped: return Color.fromOKLCH(l: 0.6, c: 0.15, h: 25)
        case .completed: return Color.fromOKLCH(l: 0.65, c: 0.2, h: 145)
        }
    }
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
        case .dislike: return .orange
        case .none: return .secondary
        }
    }

    var emoji: String {
        switch self {
        case .love: return "♥"
        case .like: return "👍"
        case .dislike: return "👎"
        case .none: return ""
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
    // Movie & Shared Moods
    case fun = "Vibey"
    case heavy = "Deep"
    case tense = "Intense"
    case wowed = "Epic"
    case cozy = "Warm"
    case creeped = "Eerie"
    case mindBlown = "Wild"
    case meh = "Chill"
    case firedUp = "Hype"

    // TV Show Specific Moods (Short, Punchy Titles with Unique Emojis)
    case binge = "Binge"
    case comfort = "Cozy"
    case cliffhanger = "Twisty"
    case slowBurn = "Slow Burn"
    case weeklyEvent = "Weekly"
    case guiltyPleasure = "Guilty"
    case masterpieceRun = "Peak"

    /// Returns curated moods tailored for Movies vs TV Shows
    static func moods(for type: MediaType?) -> [Mood] {
        guard let type = type else { return allCases }
        switch type {
        case .movie:
            return [.mindBlown, .fun, .heavy, .tense, .wowed, .cozy, .creeped, .firedUp, .meh]
        case .tvShow:
            return [.binge, .comfort, .cliffhanger, .slowBurn, .weeklyEvent, .guiltyPleasure, .masterpieceRun, .firedUp, .meh]
        }
    }

    var emoji: String {
        switch self {
        case .fun: return "face.smiling.fill"
        case .heavy: return "heart.fill"
        case .tense: return "bolt.fill"
        case .wowed: return "sparkle"
        case .cozy: return "sun.max.fill"
        case .creeped: return "eye.fill"
        case .mindBlown: return "brain.head.profile"
        case .meh: return "cup.and.saucer.fill"
        case .firedUp: return "flame.fill"
        case .binge: return "tv.fill"
        case .comfort: return "sofa.fill"
        case .cliffhanger: return "bolt.fill"
        case .slowBurn: return "brain.head.profile"
        case .weeklyEvent: return "calendar"
        case .guiltyPleasure: return "theatermasks.fill"
        case .masterpieceRun: return "trophy.fill"
        }
    }

    var emojiChar: String {
        switch self {
        case .fun: return "😄"
        case .heavy: return "🥺"
        case .tense: return "⚡"
        case .wowed: return "🤩"
        case .cozy: return "🫶"
        case .creeped: return "👻"
        case .mindBlown: return "🤯"
        case .meh: return "☕"
        case .firedUp: return "🔥"
        case .binge: return "📺"
        case .comfort: return "🛋️"
        case .cliffhanger: return "⚡"
        case .slowBurn: return "🧠"
        case .weeklyEvent: return "🗓️"
        case .guiltyPleasure: return "🎭"
        case .masterpieceRun: return "🏆"
        }
    }

    var color: Color {
        switch self {
        case .fun: return Color(red: 0.9, green: 0.55, blue: 0.15)
        case .heavy: return Color(red: 0.3, green: 0.35, blue: 0.55)
        case .tense: return Color(red: 0.85, green: 0.25, blue: 0.2)
        case .wowed: return Color(red: 0.6, green: 0.35, blue: 0.9)
        case .cozy: return Color(red: 0.85, green: 0.3, blue: 0.45)
        case .creeped: return Color(red: 0.35, green: 0.35, blue: 0.4)
        case .mindBlown: return Color(red: 0.1, green: 0.6, blue: 0.65)
        case .meh: return Color(red: 0.5, green: 0.5, blue: 0.5)
        case .firedUp: return Color(red: 0.9, green: 0.45, blue: 0.15)
        case .binge: return Color(red: 0.95, green: 0.35, blue: 0.15)
        case .comfort: return Color(red: 0.85, green: 0.55, blue: 0.25)
        case .cliffhanger: return Color(red: 0.9, green: 0.2, blue: 0.25)
        case .slowBurn: return Color(red: 0.35, green: 0.45, blue: 0.75)
        case .weeklyEvent: return Color(red: 0.95, green: 0.65, blue: 0.1)
        case .guiltyPleasure: return Color(red: 0.85, green: 0.3, blue: 0.6)
        case .masterpieceRun: return Color(red: 0.95, green: 0.75, blue: 0.15)
        }
    }

    /// Map old/variant mood values to the current set so existing data is never orphaned.
    static func normalized(_ value: String) -> Mood? {
        switch value {
        case "Awe", "Inspired": return .wowed
        case "Joy", "Amused", "Calm", "Relaxed": return .fun
        case "Nothing", "Flat": return .meh
        case "Moved": return .heavy
        case "Thrilled": return .tense
        case "Binge-Worthy", "Binge", "Bingeable": return .binge
        case "Comfort Rewatch", "Cozy", "Rewatch": return .comfort
        case "Cliffhanger", "Twisty": return .cliffhanger
        case "Slow Burn", "Slowburn", "Deep ": return .slowBurn
        case "Weekly Hype", "Weekly": return .weeklyEvent
        case "Guilty Pleasure", "Guilty": return .guiltyPleasure
        case "Peak TV", "Peak", "Masterpiece": return .masterpieceRun
        default: return Mood(rawValue: value)
        }
    }
}
