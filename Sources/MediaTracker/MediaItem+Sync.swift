import Foundation
import SwiftData

extension MediaItem {
    func syncCachedProperties(now: Date = Date()) {
        // Phase 4 Optimization: Avoid relationship faulting cascades during sync
        // If details aren't loaded, don't force a sync unless explicitly requested.
        let currentState = state ?? .wishlist

        syncCastCache()

        if type == .movie {
            syncMovieProperties()
        } else if type == .tvShow {
            syncTVProperties(now: now, currentState: currentState)
        }

        // Phase 1 Modularization: Use Centralized Badge Engine
        if let result = BadgeEngine.calculateBadge(for: self, now: now) {
            self.storedSmartBadgeLabel = result.label
            self.storedSmartBadgeIcon = result.icon
            self.storedSmartBadgeIsSparkle = result.isSparkle
        } else {
            self.storedSmartBadgeLabel = nil
            self.storedSmartBadgeIcon = nil
            self.storedSmartBadgeIsSparkle = false
        }

        if let airDate = cachedNextAiringDate {
            self.storedIsUpcoming = airDate > now
        } else {
            self.storedIsUpcoming = false
        }
        updateSearchableText()
    }

    func syncCastCache() {
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

    func syncMovieProperties() {
        guard let movie = movieDetails else { return }
        self.cachedGenres = movie.genres
        self.cachedCreators = movie.creators
        self.cachedLanguage = movie.originalLanguage
        self.cachedNextAiringDate = self.releaseDate
        self.cachedRuntime = movie.runtime
    }

    func syncTVProperties(now: Date, currentState: MediaState) {
        guard let tv = tvShowDetails else { return }
        
        // Force consistency: If series is marked as Completed, all episodes MUST be watched (if enabled).
        let autoMark = UserDefaults.standard.bool(forKey: "auto_mark_episodes_watched")
        if autoMark && currentState == .completed && tv.watchedEpisodesCount < tv.totalEpisodesCount {
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
                let sortedSeasons = tv.seasons.sorted { $0.seasonNumber < $1.seasonNumber }
                for season in sortedSeasons {
                    let sortedEpisodes = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
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
        let relevantSeasons = tv.seasons.filter { $0.seasonNumber > 0 }
        if !relevantSeasons.isEmpty {
            var totalCount = 0
            var watchedCount = 0
            var airedCount = 0
            var firstUnwatched: TVEpisode? = nil
            let sortedSeasons = relevantSeasons.sorted { $0.seasonNumber < $1.seasonNumber }
            
            for season in sortedSeasons {
                let sortedEpisodes = season.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
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

    func checkOverallCompletion() {
        if type == .tvShow, let tv = tvShowDetails {
            // Use denormalized counts for O(1) check
            if tv.totalEpisodesCount > 0 && tv.watchedEpisodesCount >= tv.totalEpisodesCount {
                if state != .completed && state != .rewatching {
                    self.state = .completed
                }
            }
        }
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
}
