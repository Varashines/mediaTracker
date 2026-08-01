import Foundation
import SwiftData

extension MediaItem {
    func syncCachedProperties(now: Date = Date(), dirty: CacheDirtyFlags = .all) {
        let currentState = state ?? .wishlist
        let fullSync = dirty.contains(.all)

        if dirty.contains(.cast) || fullSync {
            syncCastCache(force: fullSync)
        }

        if dirty.contains(.metadata) || dirty.contains(.progress) || fullSync {
            let skipNetwork = !fullSync && !dirty.contains(.metadata)
            if type == .movie {
                syncMovieProperties(skipNetwork: skipNetwork)
            } else if type == .tvShow {
                syncTVProperties(now: now, currentState: currentState, skipNetwork: skipNetwork, forceRecalculate: fullSync || dirty.contains(.progress))
            }
        }

        if dirty.contains(.badge) || fullSync {
            let oldLabel = storedSmartBadgeLabel
            let oldSparkle = storedSmartBadgeIsSparkle
            if let result = BadgeEngine.calculateBadge(for: self, now: now) {
                if result.label.rawValue != oldLabel || result.isSparkle != oldSparkle {
                    self.storedSmartBadgeLabel = result.label.rawValue
                    self.storedSmartBadgeIsSparkle = result.isSparkle
                }
            } else {
                if oldLabel != nil || oldSparkle != false {
                    self.storedSmartBadgeLabel = nil
                    self.storedSmartBadgeIsSparkle = false
                }
            }

            if oldLabel != storedSmartBadgeLabel {
                BadgeEngine.enqueueBadgeChange(old: oldLabel, new: storedSmartBadgeLabel)
            }
        }

        if let airDate = cachedNextAiringDate ?? releaseDate {
            self.storedIsUpcoming = airDate > now
        } else {
            self.storedIsUpcoming = false
        }

        if dirty.contains(.searchable) || fullSync {
            updateSearchableText()
        }
    }

    func syncCastCache(force: Bool = false) {
        guard let context = modelContext else { return }
        
        if !force, !storedCast.isEmpty { return }
        
        // Defensive: Use direct fetch instead of relationship to avoid "ghost objects" during background merges
        let currentID = self.id
        let descriptor = FetchDescriptor<CastMember>(predicate: #Predicate { $0.mediaID == currentID })
        
        do {
            let castMembers = try context.fetch(descriptor)
            if !castMembers.isEmpty {
                // Phase 5: Strict Deduplication by Name + Character
                var seen = Set<String>()
                var uniqueList: [SimpleCastMember] = []
                
                // Defensive: skip any objects that were deleted/detached during a concurrent merge
                let sortedRaw = castMembers
                    .liveModels
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
                    if uniqueList.count >= 30 { break }
                }
                
                self.storedCast = uniqueList
            }
        } catch {
            AppLogger.debug("🔍 syncCastCache: Fetch failed: \(error)", logger: AppLogger.sync)
        }
    }

    func syncMovieProperties(skipNetwork: Bool = false) {
        guard let movie = movieDetails else { return }
        self.cachedGenres = GenreMapper.standardize(movie.genres)
        self.cachedCreators = movie.creators
        self.cachedLanguage = movie.originalLanguage
        self.cachedNextAiringDate = self.releaseDate
        self.cachedRuntime = movie.runtime
        if !skipNetwork {
            self.cachedNetwork = Self.normalizeCommaSeparated(movie.network)
            self.cachedNetworkLogoPath = Self.normalizeCommaSeparated(movie.networkLogoPath)
        }
    }

    func syncTVProperties(now: Date, currentState: MediaState, skipNetwork: Bool = false, forceRecalculate: Bool = false) {
        guard let tv = tvShowDetails else { return }
        
        self.cachedGenres = GenreMapper.standardize(tv.genres)
        self.cachedCreators = tv.creators
        self.cachedLanguage = tv.originalLanguage
        if !skipNetwork {
            self.cachedNetwork = Self.normalizeCommaSeparated(tv.network)
            self.cachedNetworkLogoPath = Self.normalizeCommaSeparated(tv.networkLogoPath)
        }
        
        // Use Unified Logic - Only force recalculate if explicitly requested to heal drift
        let progressResult = tv.calculateProgress(now: now, forceRecalculate: forceRecalculate)
        self.cachedRuntime = progressResult.totalRuntime
        self.cachedWatchedEpisodeCount = progressResult.watchedCount
        self.remainingEpisodesCount = progressResult.remainingCount
        
        if progressResult.totalCount > 0 {
            self.cachedEpisodeRuntime = progressResult.totalRuntime / progressResult.totalCount
            let progress = Double(progressResult.watchedCount) / Double(progressResult.totalCount)
            
            self.storedProgress = progress
            self.storedWatchProgressLabel = "\(progressResult.watchedCount)/\(progressResult.totalCount) EP"

            // Unified Auto-advance State Logic (runs before auto-mark so state is updated first)
            // Set stateValue directly to avoid re-triggering syncCachedProperties via the state setter
            if progress >= 1.0 && currentState != .completed && currentState != .rewatching && currentState != .onHold && currentState != .dropped {
                self.stateValue = MediaState.completed.rawValue
                self.lastInteractionDate = now
                self.lastStateChangeDate = now
            } else if progress > 0 && progress < 1.0 && (currentState == .wishlist || currentState == .completed) {
                self.stateValue = MediaState.active.rawValue
                self.lastInteractionDate = now
                self.lastStateChangeDate = now
            } else if progress == 0 && (currentState == .active || currentState == .completed) {
                self.stateValue = MediaState.wishlist.rawValue
                self.lastInteractionDate = now
                self.lastStateChangeDate = now
            }

            // Auto-mark: only if state is still Completed after auto-advance
            // This prevents re-marking when user unmarks an episode (progress drops → state changes to Active)
            if stateValue == "Completed" {
                let autoMark = UserDefaults.standard.bool(forKey: UserDefaultsKeys.autoMarkEpisodesWatched.rawValue)
                if autoMark && tv.watchedEpisodesCount < tv.totalEpisodesCount {
                    let liveSeasons = tv.seasons.liveModels
                    var newlyMarked = 0
                    for season in liveSeasons {
                        let liveEps = season.episodes.liveModels
                        var seasonMarked = 0
                        for ep in liveEps where !ep.isWatched {
                            ep.markWatched(true)
                            newlyMarked += 1
                            seasonMarked += 1
                        }
                        season.watchedEpisodesCount += seasonMarked
                    }
                    // Update denormalized counts directly — avoids a full traversal re-scan
                    tv.watchedEpisodesCount += newlyMarked
                    let newRemaining = max(0, (progressResult.remainingCount) - newlyMarked)
                    self.remainingEpisodesCount = newRemaining
                    self.cachedWatchedEpisodeCount = tv.watchedEpisodesCount

                    if progressResult.totalCount > 0 {
                        let newProgress = Double(tv.watchedEpisodesCount) / Double(progressResult.totalCount)
                        self.storedProgress = newProgress
                        self.storedWatchProgressLabel = "\(tv.watchedEpisodesCount)/\(progressResult.totalCount) EP"
                        self.cachedEpisodeRuntime = progressResult.totalRuntime / progressResult.totalCount
                    }

                    // All episodes now watched — no firstUnwatched
                    self.storedNextEpisodeLabel = nil
                    self.cachedNextAiringDate = tv.nextEpisodeDate
                } else {
                    // No auto-mark needed, use original progressResult
                    if let next = progressResult.firstUnwatched {
                        self.storedNextEpisodeLabel = "S\(next.seasonNumber) E\(next.episodeNumber)"
                        self.cachedNextAiringDate = next.airDateAsDate ?? tv.nextEpisodeDate
                    } else {
                        self.storedNextEpisodeLabel = nil
                        self.cachedNextAiringDate = tv.nextEpisodeDate
                    }
                }
            } else {
                // State is not Completed, no auto-mark, use original progressResult
                if let next = progressResult.firstUnwatched {
                    self.storedNextEpisodeLabel = "S\(next.seasonNumber) E\(next.episodeNumber)"
                    self.cachedNextAiringDate = next.airDateAsDate ?? tv.nextEpisodeDate
                } else {
                    self.storedNextEpisodeLabel = nil
                    self.cachedNextAiringDate = tv.nextEpisodeDate
                }
            }
        } else {
            self.storedProgress = 0
            self.storedWatchProgressLabel = nil
            self.storedNextEpisodeLabel = nil
            self.cachedNextAiringDate = tv.nextEpisodeDate
        }
    }

    func updateSearchableText() {
        let truncatedOverview = String(overview.prefix(200))
        var text = "\(title) \(truncatedOverview)"
        
        // Phase 4 Optimization: Use cached properties to avoid relationship faulting
        if !cachedGenres.isEmpty {
            text += " \(cachedGenres.joined(separator: " "))"
        }
        
        if !cachedCreators.isEmpty {
            text += " \(cachedCreators.joined(separator: " "))"
        }
        
        if !storedCast.isEmpty {
            text += " \(storedCast.map { $0.name }.joined(separator: " "))"
        }
        
        if let network = cachedNetwork {
            text += " \(network)"
        }
        
        if let lang = cachedLanguage {
            text += " \(lang)"
        }
        
        self.searchableText = text.lowercased()
    }

    static func normalizeCommaSeparated(_ value: String?) -> String? {
        guard let value else { return nil }
        let components = value.splitCommaTrimmed()
        guard !components.isEmpty else { return nil }
        return components.joined(separator: ", ")
    }
}

extension String {
    func splitCommaTrimmed() -> [String] {
        self.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
