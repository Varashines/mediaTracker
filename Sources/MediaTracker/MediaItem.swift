import Foundation
import SwiftData

@Model
final class MediaItem: Identifiable {
    var id: String
    var title: String
    var overview: String
    var posterURL: String?
    var backdropURL: String?
    var releaseDate: Date?
    var typeValue: String = "Movie"
    var stateValue: String = "Wishlist"
    var tasteValue: String = "None"
    var themeColorHex: String?
    var lastInteractionDate: Date?
    var lastStateChangeDate: Date?
    var dateAdded: Date?
    var lastUpdated: Date?
    var isDeleted: Bool = false
    
    // Cached values for filtering/grid
    var cachedGenres: [String] = []
    var cachedCreators: [String] = []
    var cachedLanguage: String?
    var cachedNetwork: String?
    var cachedNetworkLogoPath: String?
    var cachedNextAiringDate: Date?
    var cachedRuntime: Int?
    var cachedWatchedEpisodeCount: Int?
    var remainingEpisodesCount: Int?

    var storedSmartBadgeLabel: String?
    var storedSmartBadgeIcon: String?
    var storedSmartBadgeIsSparkle: Bool = false
    var storedIsUpcoming: Bool = false
    var storedNextEpisodeLabel: String?
    var storedWatchProgressLabel: String?
    var storedProgress: Double?
    var searchableText: String = ""
    var storedCast: [SimpleCastMember] = []
    
    var collections: [MediaCollection]?

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
        self.lastInteractionDate = Date()
        self.lastStateChangeDate = Date()
        self.dateAdded = Date()
    }

    var type: MediaType? {
        get { MediaType(rawValue: typeValue) }
        set { typeValue = newValue?.rawValue ?? "Movie" }
    }

    var taste: TasteValue? {
        get { TasteValue(rawValue: tasteValue) }
        set { tasteValue = newValue?.rawValue ?? "None" }
    }
    var state: MediaState? {
        get { MediaState(rawValue: stateValue) }
        set { stateValue = newValue?.rawValue ?? "Wishlist" }
    }

    var movieDetails: MovieDetails?
    var tvShowDetails: TVShowDetails?
    
    static func availableStates(for type: MediaType, progress: Double?) -> [MediaState] {
        let progressVal = progress ?? 0
        if progressVal >= 1.0 {
            return [.completed, .rewatching]
        } else if progressVal > 0 {
            return [.active, .onHold, .dropped, .rewatching, .completed]
        }
        return MediaState.allCases
    }
}

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
        
        // Phase 4 Optimization: Use cached properties to avoid relationship faulting
        if !cachedGenres.isEmpty {
            text += " \(cachedGenres.joined(separator: " "))"
        }
        
        if !storedCast.isEmpty {
            text += " \(storedCast.map { $0.name }.joined(separator: " "))"
        }
        
        if let network = cachedNetwork {
            text += " \(network)"
        }
        
        self.searchableText = text.lowercased()
    }

    func checkOverallCompletion() {
        if type == .tvShow, let tv = tvShowDetails {
            let episodes = tv.seasons.flatMap { $0.episodes }
            if !episodes.isEmpty && episodes.allSatisfy({ $0.isWatched }) {
                if state != .completed && state != .rewatching {
                    state = .completed
                    lastStateChangeDate = Date()
                }
            }
        }
    }

    func syncCachedProperties() {
        // Phase 4 Optimization: Avoid relationship faulting cascades during sync
        // If details aren't loaded, don't force a sync unless explicitly requested.
        let now = Date()
        let currentState = state ?? .wishlist

        syncCastCache()

        if type == .movie {
            syncMovieProperties()
        } else if type == .tvShow {
            syncTVProperties(now: now, currentState: currentState)
        }

        // Phase 1 Modularization: Use Centralized Badge Engine
        if let result = BadgeEngine.calculateBadge(for: self) {
            self.storedSmartBadgeLabel = result.label
            self.storedSmartBadgeIcon = result.icon
            self.storedSmartBadgeIsSparkle = result.isSparkle
        } else {
            self.storedSmartBadgeLabel = nil
            self.storedSmartBadgeIcon = nil
            self.storedSmartBadgeIsSparkle = false
        }

        self.storedIsUpcoming = isUpcoming
        updateSearchableText()
    }

    private func syncCastCache() {
        guard let context = modelContext else { return }
        
        // Defensive: Use direct fetch instead of relationship to avoid "ghost objects" during background merges
        let currentID = self.id
        let descriptor = FetchDescriptor<CastMember>(predicate: #Predicate { $0.mediaID == currentID })
        
        do {
            let castMembers = try context.fetch(descriptor)
            if !castMembers.isEmpty {
                // Phase 5: Strict Deduplication by Name + Character
                var seen = Set<String>()
                var uniqueList: [SimpleCastMember] = []
                
                let sortedRaw = castMembers
                    .filter { $0.characterName != "Creator" && $0.characterName != "Director" }
                    .sorted { $0.order < $1.order }
                
                for member in sortedRaw {
                    let key = "\(member.name)|\(member.characterName)"
                    if !seen.contains(key) {
                        seen.insert(key)
                        uniqueList.append(SimpleCastMember(
                            id: member.uniqueID ?? UUID().uuidString,
                            name: member.name,
                            characterName: member.characterName,
                            profileURL: member.profileURL,
                            order: member.order
                        ))
                    }
                    if uniqueList.count >= 10 { break }
                }
                
                self.storedCast = uniqueList
            }
        } catch {
            print("🔍 syncCastCache: Fetch failed: \(error)")
        }
    }

    private func syncMovieProperties() {
        guard let movie = movieDetails else { return }
        self.cachedGenres = movie.genres
        self.cachedCreators = movie.creators
        self.cachedLanguage = movie.originalLanguage
        self.cachedNextAiringDate = self.releaseDate
        self.cachedRuntime = movie.runtime
    }

    private func syncTVProperties(now: Date, currentState: MediaState) {
        guard let tv = tvShowDetails else { return }
        
        // Force consistency: If series is marked as Completed, all episodes MUST be watched.
        if currentState == .completed && tv.watchedEpisodesCount < tv.totalEpisodesCount {
            for season in tv.seasons {
                for ep in season.episodes where !ep.isWatched {
                    ep.isWatched = true
                }
            }
            tv.refreshCounts()
        }

        self.cachedGenres = tv.genres
        self.cachedCreators = tv.creators
        self.cachedLanguage = tv.originalLanguage
        self.cachedNetwork = tv.network
        self.cachedNetworkLogoPath = tv.networkLogoPath
        
        let watchedEpisodes = tv.seasons.flatMap { $0.episodes }.filter { $0.isWatched }
        self.cachedRuntime = watchedEpisodes.reduce(0) { $0 + ($1.runtime ?? 0) }

        // Phase 2 Optimization: Use Denormalized Counts if available
        if tv.totalEpisodesCount > 0 {
            let totalCount = tv.totalEpisodesCount
            let watchedCount = tv.watchedEpisodesCount
            self.cachedWatchedEpisodeCount = watchedCount
            
            // Calculate progress O(1)
            let progress = Double(watchedCount) / Double(totalCount)
            if progress >= 1.0 && currentState != .completed && currentState != .rewatching {
                self.state = .completed
                self.lastStateChangeDate = now
            } else if progress > 0 && progress < 1.0 && (currentState == .wishlist || currentState == .completed) {
                self.state = .active
                self.lastStateChangeDate = now
            }

            self.storedProgress = progress
            self.storedWatchProgressLabel = "\(watchedCount)/\(totalCount) EP"
            
            if currentState == .active || currentState == .wishlist {
                // Optimized firstUnwatched search (stops at first match)
                var firstUnwatched: TVEpisode? = nil
                let sortedSeasons = tv.seasons.filter { !$0.isDeleted }.sorted { $0.seasonNumber < $1.seasonNumber }
                for season in sortedSeasons {
                    let sortedEpisodes = season.episodes.filter { !$0.isDeleted }.sorted { $0.episodeNumber < $1.episodeNumber }
                    if let next = sortedEpisodes.first(where: { !$0.isWatched }) {
                        firstUnwatched = next
                        break
                    }
                }
                
                if let next = firstUnwatched {
                    self.storedNextEpisodeLabel = "S\(next.seasonNumber) E\(next.episodeNumber)"
                    self.cachedNextAiringDate = next.airDateAsDate ?? tv.nextEpisodeDate
                } else {
                    self.storedNextEpisodeLabel = nil
                    self.cachedNextAiringDate = tv.nextEpisodeDate
                }
            }
            return
        }

        // Fallback for legacy data or first-load
        let relevantSeasons = tv.seasons.filter { $0.seasonNumber > 0 && !$0.isDeleted }
        if !relevantSeasons.isEmpty {
            var totalCount = 0
            var watchedCount = 0
            var airedCount = 0
            var firstUnwatched: TVEpisode? = nil
            let sortedSeasons = relevantSeasons.sorted { $0.seasonNumber < $1.seasonNumber }
            
            for season in sortedSeasons {
                let sortedEpisodes = season.episodes.filter { !$0.isDeleted }.sorted { $0.episodeNumber < $1.episodeNumber }
                for ep in sortedEpisodes {
                    totalCount += 1
                    if ep.isWatched { watchedCount += 1 } 
                    else if firstUnwatched == nil { firstUnwatched = ep }
                    if (ep.airDateAsDate ?? .distantFuture) <= now { airedCount += 1 }
                }
            }

            if totalCount == 0 {
                self.storedProgress = 0
                self.storedWatchProgressLabel = nil
                self.storedNextEpisodeLabel = nil
                self.cachedNextAiringDate = tv.nextEpisodeDate
                self.remainingEpisodesCount = 0
                tv.remainingEpisodesCount = 0
            } else {
                let remaining = airedCount - watchedCount
                self.remainingEpisodesCount = max(0, remaining)
                tv.remainingEpisodesCount = max(0, remaining)

                let progress = Double(watchedCount) / Double(totalCount)
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
                self.storedWatchProgressLabel = "\(watchedCount)/\(totalCount) EP"

                if let next = firstUnwatched {
                    self.storedNextEpisodeLabel = "S\(next.seasonNumber) E\(next.episodeNumber)"
                    self.cachedNextAiringDate = next.airDateAsDate ?? tv.nextEpisodeDate
                } else {
                    self.storedNextEpisodeLabel = nil
                    self.cachedNextAiringDate = tv.nextEpisodeDate
                }
            }
        }
    }
}
