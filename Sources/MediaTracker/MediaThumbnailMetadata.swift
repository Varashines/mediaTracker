import Foundation
import SwiftData

struct MediaThumbnailMetadata: Sendable, Identifiable, Equatable {
    static func == (lhs: MediaThumbnailMetadata, rhs: MediaThumbnailMetadata) -> Bool {
        return lhs.id == rhs.id &&
               lhs.progress == rhs.progress &&
               lhs.smartBadgeLabel == rhs.smartBadgeLabel &&
               lhs.state == rhs.state
    }

    let id: PersistentIdentifier
    let itemID: String
    let title: String
    let posterURL: String?
    let backdropURL: String?
    let releaseDate: Date?
    let type: MediaType?
    let state: MediaState?
    let themeColorHex: String?
    let progress: Double?
    let watchProgress: String?
    let nextEpisodeToWatchLabel: String?
    let isUpcoming: Bool
    let badgeText: String?
    let smartBadgeLabel: String?
    let isSparkleBadge: Bool
    let remainingCount: Int?
    let nextAiringDate: Date?
    let genres: [String]
    let recommendationReason: String?
    let lastInteractionDate: Date?

    var versionHash: String { "\(id.hashValue)_\(progress ?? 0)" }

    var formattedMetadata: String {
        let year = releaseDate.flatMap { Calendar.current.dateComponents([.year], from: $0).year.map { String($0) } } ?? ""
        if let firstGenre = genres.first {
            return "\(year) • \(firstGenre)"
        }
        return year
    }

    init(item: MediaItem, recommendationReason: String? = nil) {
        self.id = item.persistentModelID
        self.itemID = item.id
        self.title = item.title
        self.posterURL = item.posterURL
        self.backdropURL = item.backdropURL
        self.releaseDate = item.releaseDate
        self.type = item.type
        self.state = item.state
        self.themeColorHex = item.themeColorHex
        self.progress = item.storedProgress
        self.watchProgress = item.storedWatchProgressLabel
        self.nextEpisodeToWatchLabel = item.storedNextEpisodeLabel
        self.isUpcoming = item.storedIsUpcoming
        self.badgeText = item.gridBadgeText
        self.smartBadgeLabel = item.storedSmartBadgeLabel
        self.isSparkleBadge = item.storedSmartBadgeIsSparkle
        self.remainingCount = item.remainingEpisodesCount
        self.nextAiringDate = item.cachedNextAiringDate
        self.recommendationReason = recommendationReason
        self.genres = item.cachedGenres
        self.lastInteractionDate = item.lastInteractionDate
    }

    init(id: PersistentIdentifier, title: String) {
        self.id = id
        self.itemID = ""
        self.title = title
        self.posterURL = nil
        self.backdropURL = nil
        self.releaseDate = nil
        self.type = .movie
        self.state = .wishlist
        self.themeColorHex = nil
        self.progress = nil
        self.watchProgress = nil
        self.nextEpisodeToWatchLabel = nil
        self.isUpcoming = false
        self.badgeText = nil
        self.smartBadgeLabel = nil
        self.isSparkleBadge = false
        self.remainingCount = nil
        self.nextAiringDate = nil
        self.genres = []
        self.recommendationReason = nil
        self.lastInteractionDate = nil
    }

    /// Preview/test initializer with full control over all fields
    init(
        id: PersistentIdentifier,
        title: String,
        type: MediaType = .movie,
        state: MediaState = .wishlist,
        smartBadgeLabel: String? = nil,
        isSparkleBadge: Bool = false,
        progress: Double? = nil,
        remainingCount: Int? = nil,
        isUpcoming: Bool = false,
        themeColorHex: String? = nil,
        posterURL: String? = nil
    ) {
        self.id = id
        self.itemID = ""
        self.title = title
        self.posterURL = posterURL
        self.backdropURL = nil
        self.releaseDate = nil
        self.type = type
        self.state = state
        self.themeColorHex = themeColorHex
        self.progress = progress
        self.watchProgress = nil
        self.nextEpisodeToWatchLabel = nil
        self.isUpcoming = isUpcoming
        self.badgeText = nil
        self.smartBadgeLabel = smartBadgeLabel
        self.isSparkleBadge = isSparkleBadge
        self.remainingCount = remainingCount
        self.nextAiringDate = nil
        self.genres = []
        self.recommendationReason = nil
        self.lastInteractionDate = nil
    }
}

struct PaginatedResult: Sendable {
    let displayed: [MediaThumbnailMetadata]
    let featuredUpcoming: [MediaThumbnailMetadata]
    let recentlyAdded: [MediaThumbnailMetadata]
    let homeContinueWatching: [MediaThumbnailMetadata]
    let spotlightHero: MediaThumbnailMetadata?
    let grouped: [(String, [MediaThumbnailMetadata])]
    let totalCount: Int
}
