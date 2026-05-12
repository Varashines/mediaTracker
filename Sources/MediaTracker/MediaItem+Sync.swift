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
            self.storedSmartBadgeIsSparkle = result.isSparkle
        } else {
            self.storedSmartBadgeLabel = nil
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
                    ep.markWatched(true)
                }
            }
        }

        self.cachedGenres = tv.genres
        self.cachedCreators = tv.creators
        self.cachedLanguage = tv.originalLanguage
        self.cachedNetwork = tv.network
        self.cachedNetworkLogoPath = tv.networkLogoPath
        
        // Use Unified Logic
        let progressResult = tv.calculateProgress(now: now)
        self.cachedRuntime = progressResult.totalRuntime
        self.cachedWatchedEpisodeCount = progressResult.watchedCount
        self.remainingEpisodesCount = progressResult.remainingCount
        
        if progressResult.totalCount > 0 {
            self.cachedEpisodeRuntime = progressResult.totalRuntime / progressResult.totalCount
            let progress = Double(progressResult.watchedCount) / Double(progressResult.totalCount)
            
            // Auto-advance State
            if progress >= 1.0 && currentState != .completed && currentState != .rewatching {
                self.state = .completed
                self.lastStateChangeDate = now
            } else if progress > 0 && progress < 1.0 && (currentState == .wishlist || currentState == .completed) {
                self.state = .active
                self.lastStateChangeDate = now
            }

            self.storedProgress = progress
            self.storedWatchProgressLabel = "\(progressResult.watchedCount)/\(progressResult.totalCount) EP"
            
            if let next = progressResult.firstUnwatched {
                self.storedNextEpisodeLabel = "S\(next.seasonNumber) E\(next.episodeNumber)"
                self.cachedNextAiringDate = next.airDateAsDate ?? tv.nextEpisodeDate
            } else {
                self.storedNextEpisodeLabel = nil
                self.cachedNextAiringDate = tv.nextEpisodeDate
            }
        } else {
            self.storedProgress = 0
            self.storedWatchProgressLabel = nil
            self.storedNextEpisodeLabel = nil
            self.cachedNextAiringDate = tv.nextEpisodeDate
        }
    }

    func checkOverallCompletion() {
        if type == .tvShow, let tv = tvShowDetails {
            // Use denormalized counts for O(1) check
            if tv.totalEpisodesCount > 0 {
                if tv.watchedEpisodesCount >= tv.totalEpisodesCount {
                    if state != .completed && state != .rewatching {
                        self.state = .completed
                    }
                } else if tv.watchedEpisodesCount > 0 {
                    // Transition to active when a user starts watching
                    if state == .wishlist {
                        self.state = .active
                    }
                } else if tv.watchedEpisodesCount == 0 {
                    // Revert to wishlist if they unwatch everything
                    if state == .active {
                        self.state = .wishlist
                    }
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
