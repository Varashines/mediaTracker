import Foundation
import SwiftData

struct CacheDirtyFlags: OptionSet, Sendable {
    let rawValue: Int
    static let progress   = CacheDirtyFlags(rawValue: 1 << 0)
    static let badge      = CacheDirtyFlags(rawValue: 1 << 1)
    static let metadata   = CacheDirtyFlags(rawValue: 1 << 2)
    static let cast       = CacheDirtyFlags(rawValue: 1 << 3)
    static let searchable = CacheDirtyFlags(rawValue: 1 << 4)
    static let all: CacheDirtyFlags = [.progress, .badge, .metadata, .cast, .searchable]
}

@Model
final class MediaItem: Identifiable {
    #Index<MediaItem>([
        \.stateValue,
        \.isSoftDeleted,
        \.typeValue,
        \.storedIsUpcoming,
        \.tasteValue,
        \.storedSmartBadgeLabel
    ])

    @Attribute(.unique)
    var id: String
    var title: String
    var overview: String
    var posterURL: String?
    var customPosterURL: String?
    var customLogoURL: String?
    var mood: String?
    var backdropURL: String?
    var releaseDate: Date?
    var typeValue: String = "Movie"
    var stateValue: String = "Wishlist"
    var tasteValue: String = "None"
    var themeColorHex: String?
    var themeColorSourceURL: String?
    /// Secondary accent + muted wash from the poster palette (premium detail view).
    var themeSecondaryColorHex: String?
    var themeMutedColorHex: String?
    var lastInteractionDate: Date?
    var lastStateChangeDate: Date?
    var dateAdded: Date?
    var lastUpdated: Date?
    var isSoftDeleted: Bool = false
    var softDeletedAt: Date?
    
    // Cached values for filtering/grid
    var cachedGenres: [String] = []
    var cachedCreators: [String] = []
    var cachedLanguage: String?
    var cachedNetwork: String?
    var cachedNetworkLogoPath: String?
    var cachedWatchProviders: [String] = []
    var cachedWatchProviderLogoPaths: [String]?
    var cachedNextAiringDate: Date?
    var cachedRuntime: Int?
    var cachedEpisodeRuntime: Int?
    var cachedWatchedEpisodeCount: Int?
    var remainingEpisodesCount: Int?
    /// Number of seasons for a TV show. O(1) lookup for taste weight tiers.
    var cachedSeasonCount: Int = 0

    var storedSmartBadgeLabel: String?
    var storedSmartBadgeIsSparkle: Bool = false
    var storedIsUpcoming: Bool = false
    var storedNextEpisodeLabel: String?
    var storedWatchProgressLabel: String?
    var storedProgress: Double?
    var searchableText: String = ""
    var storedCast: [SimpleCastMember] = []
    var cachedTrailerKey: String?
    var titleLogoURL: String?
    
    var collections: [MediaCollection] = []

    var displayCast: [SimpleCastMember] {
        return storedCast
    }

    init(id: String, title: String, overview: String, posterURL: String? = nil, backdropURL: String? = nil, releaseDate: Date? = nil, type: MediaType? = .movie) {
        self.id = id
        self.title = title
        self.overview = overview
        self.posterURL = posterURL
        self.backdropURL = backdropURL
        self.releaseDate = releaseDate
        self.typeValue = type?.rawValue ?? "Movie"
        let now = Date()
        self.lastInteractionDate = now
        self.lastStateChangeDate = now
        self.dateAdded = now
    }

    nonisolated func commitChange(dirty: CacheDirtyFlags = .all) {
        syncCachedProperties(dirty: dirty)
        nonisolated(unsafe) let context = modelContext
        let pid = persistentModelID
        Task { @MainActor in
            if let ctx = context {
                SaveCoordinator.shared.requestSave(ctx)
            }
            MediaStateService.shared.postMediaStateChanged(itemID: pid)
        }
    }

    var type: MediaType? {
        get { MediaType(rawValue: typeValue) }
        set { typeValue = newValue?.rawValue ?? "Movie" }
    }

    var taste: TasteValue? {
        get { TasteValue(rawValue: tasteValue) }
        set { 
            let old = tasteValue
            tasteValue = newValue?.rawValue ?? "None"
            if old != tasteValue {
                lastInteractionDate = Date()
                syncCachedProperties(dirty: [.badge, .searchable])
            }
        }
    }
    
    var state: MediaState? {
        get { MediaState(rawValue: stateValue) }
        set { 
            let old = stateValue
            stateValue = newValue?.rawValue ?? "Wishlist"
            if old != stateValue {
                lastInteractionDate = Date()
                lastStateChangeDate = Date()
                
                if typeValue == "TV Show" && stateValue == "Completed" {
                    if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoMarkEpisodesWatched.rawValue) {
                        markLoadedEpisodesAsWatched()
                        if let container = modelContext?.container {
                            let rawID = id
                            Task.detached(priority: .userInitiated) {
                                let backgroundService = BackgroundDataService(modelContainer: container)
                                await backgroundService.markAllEpisodesAsWatched(itemID: rawID)
                            }
                        }
                    }
                }
            }
        }
    }

    func markLoadedEpisodesAsWatched() {
        guard type == .tvShow, let details = tvShowDetails else { return }
        let liveSeasons = details.seasons.liveModels
        for season in liveSeasons {
            let liveEpisodes = season.episodes.liveModels
            for episode in liveEpisodes {
                episode.markWatched(true)
            }
        }
        details.recalculateCachedProperties(triggerSync: true)
        nonisolated(unsafe) let ctx = modelContext
        Task { @MainActor in
            if let ctx { SaveCoordinator.shared.forceSave(ctx) }
        }
    }

    func applyStateChange(_ newState: MediaState) {
        let didChange = stateValue != newState.rawValue
        if didChange {
            stateValue = newState.rawValue
            lastInteractionDate = Date()
            lastStateChangeDate = Date()
            
            if typeValue == "TV Show" && stateValue == "Completed" {
                if UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoMarkEpisodesWatched.rawValue) {
                    markLoadedEpisodesAsWatched()
                    if let container = modelContext?.container {
                        let rawID = id
                        Task.detached(priority: .userInitiated) {
                            let backgroundService = BackgroundDataService(modelContainer: container)
                            await backgroundService.markAllEpisodesAsWatched(itemID: rawID)
                        }
                    }
                }
            }
            
            if type == .tvShow { BadgeEngine.invalidateScan(for: persistentModelID) }
            commitChange(dirty: [.badge, .searchable])
        }
    }

    func applyTasteChange(_ newTaste: TasteValue) {
        let didChange = tasteValue != newTaste.rawValue
        if didChange {
            tasteValue = newTaste.rawValue
            lastInteractionDate = Date()
            commitChange(dirty: [.badge, .searchable])
        }
    }

    func softDelete(now: Date = Date()) {
        guard !isSoftDeleted else { return }
        isSoftDeleted = true
        softDeletedAt = now
        lastInteractionDate = now
        commitChange(dirty: [.badge])
    }

    func restoreFromSoftDelete() {
        guard isSoftDeleted else { return }
        isSoftDeleted = false
        softDeletedAt = nil
        lastInteractionDate = Date()
        commitChange(dirty: [.badge])
    }

    @Relationship(deleteRule: .cascade, inverse: \MovieDetails.item) var movieDetails: MovieDetails?
    @Relationship(deleteRule: .cascade, inverse: \TVShowDetails.item) var tvShowDetails: TVShowDetails?
    
    static func availableStates(for type: MediaType, progress: Double?) -> [MediaState] {
        let progressVal = progress ?? 0
        if progressVal >= 1.0 {
            return [.completed, .rewatching]
        } else if progressVal > 0 {
            return [.active, .onHold, .dropped, .rewatching, .completed]
        }
        // Wishlist is the default for 0 progress
        return MediaState.allCases
    }
}

extension MediaItem {
    var isUpcoming: Bool {
        storedIsUpcoming
    }

    var badgeText: String? {
        guard isUpcoming, let date = cachedNextAiringDate else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var gridBadgeText: String? { badgeText }

    var detailBadgeText: String? {
        guard isUpcoming, let date = cachedNextAiringDate else { return nil }
        if type == .tvShow {
            return date.formatted(date: .abbreviated, time: .shortened)
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }

    var requiresMaintenanceRefresh: Bool {
        guard let last = lastUpdated else { return true }
        return Date().timeIntervalSince(last) > .days30
    }
}

extension MediaItem {
    var effectivePosterURL: String? {
        customPosterURL ?? posterURL
    }

    var effectiveLogoURL: String? {
        customLogoURL ?? titleLogoURL
    }

    nonisolated(unsafe) static let thumbnailProperties: [PartialKeyPath<MediaItem>] = [
        \.id, \.title, \.posterURL, \.customPosterURL, \.backdropURL, \.releaseDate,
        \.typeValue, \.stateValue, \.tasteValue, \.themeColorHex, \.themeColorSourceURL,
        \.lastInteractionDate, \.lastStateChangeDate, \.dateAdded, \.lastUpdated,
        \.mood, \.isSoftDeleted, \.softDeletedAt,
        \.cachedGenres, \.cachedCreators, \.cachedLanguage, \.cachedNetwork,
        \.cachedNetworkLogoPath, \.cachedWatchProviders, \.cachedWatchProviderLogoPaths, \.cachedNextAiringDate, \.cachedRuntime,
        \.cachedEpisodeRuntime, \.cachedWatchedEpisodeCount, \.remainingEpisodesCount,
        \.cachedSeasonCount,
        \.storedSmartBadgeLabel, \.storedSmartBadgeIsSparkle, \.storedIsUpcoming,
        \.storedNextEpisodeLabel, \.storedWatchProgressLabel, \.storedProgress,
        \.searchableText,
        \.cachedTrailerKey, \.titleLogoURL,
    ]

    nonisolated(unsafe) static let thumbnailPropertiesWithCast: [PartialKeyPath<MediaItem>] = thumbnailProperties + [\.storedCast]
}
