import Foundation
import SwiftData

@ModelActor
actor MaintenanceService {
    func performLibraryHeal() async throws {
        let descriptor = FetchDescriptor<MediaItem>()
        let items = try modelContext.fetch(descriptor)
        
        // 0. Deduplicate MediaItems (Ensures no two items share the same TMDB ID)
        let groupedItems = Dictionary(grouping: items, by: { $0.id })
        for (id, duplicates) in groupedItems where duplicates.count > 1 {
            print("🔍 Maintenance: Found \(duplicates.count) duplicates for ID \(id)")
            let sorted = duplicates.sorted { 
                let score1 = ($0.posterURL != nil ? 2 : 0) + ($0.type == .tvShow ? 5 : 0)
                let score2 = ($1.posterURL != nil ? 2 : 0) + ($1.type == .tvShow ? 5 : 0)
                if score1 != score2 { return score1 > score2 }
                return ($0.lastInteractionDate ?? .distantPast) > ($1.lastInteractionDate ?? .distantPast)
            }
            
            // Phase 1: Merge user data into the winner
            let winner = sorted[0]
            for i in 1..<sorted.count {
                let loser = sorted[i]
                
                // Merge State (pick most advanced)
                let stateOrder: [MediaState] = [.completed, .rewatching, .active, .onHold, .dropped, .wishlist]
                if let winnerState = winner.state, let loserState = loser.state {
                    let winnerIndex = stateOrder.firstIndex(of: winnerState) ?? 99
                    let loserIndex = stateOrder.firstIndex(of: loserState) ?? 99
                    if loserIndex < winnerIndex {
                        winner.state = loserState
                    }
                }
                
                // Merge Taste
                if winner.tasteValue == "None" && loser.tasteValue != "None" {
                    winner.tasteValue = loser.tasteValue
                }
                
                // Merge Dates
                if let loserLID = loser.lastInteractionDate, (winner.lastInteractionDate == nil || loserLID > winner.lastInteractionDate!) {
                    winner.lastInteractionDate = loserLID
                }
                if let loserDA = loser.dateAdded, (winner.dateAdded == nil || loserDA < winner.dateAdded!) {
                    winner.dateAdded = loserDA
                }
                
                // Deep merge TV episodes if applicable
                if let winnerTV = winner.tvShowDetails, let loserTV = loser.tvShowDetails {
                    for loserSeason in loserTV.seasons {
                        if let winnerSeason = winnerTV.seasons.first(where: { $0.seasonNumber == loserSeason.seasonNumber }) {
                            for loserEp in loserSeason.episodes {
                                if loserEp.isWatched, let winnerEp = winnerSeason.episodes.first(where: { $0.episodeNumber == loserEp.episodeNumber }) {
                                    winnerEp.isWatched = true
                                }
                            }
                        }
                    }
                }
                
                modelContext.delete(loser)
            }
        }
        
        // Fetch fresh list after deduplication
        let sanitizedItems = try modelContext.fetch(descriptor)
        
        for item in sanitizedItems {
            await Task.yield()
            
            // 1. Migrate legacy IDs to prefixed format (prevents Movie/TV collisions)
            if !item.id.contains("_") {
                let typePrefix = item.type == .movie ? "movie" : "tv"
                item.id = "\(typePrefix)_\(item.id)"
            }

            // 2. Assign uniqueIDs to episodes and Heal Relationships
            if let tmdbIDString = item.id.split(separator: "_").last, let tmdbID = Int(tmdbIDString) {
                if let tv = item.tvShowDetails {
                    // First, deduplicate Seasons at the relationship level
                    let groupedSeasons = Dictionary(grouping: tv.seasons, by: { $0.seasonNumber })
                    for (num, duplicates) in groupedSeasons where duplicates.count > 1 {
                        print("🔍 Maintenance: Found \(duplicates.count) duplicate seasons for S\(num)")
                        let sorted = duplicates.sorted { ($0.episodes.count) > ($1.episodes.count) }
                        
                        let winner = sorted[0]
                        for i in 1..<sorted.count { 
                            let loser = sorted[i]
                            // Merge episode watch states
                            for loserEp in loser.episodes {
                                if loserEp.isWatched, let winnerEp = winner.episodes.first(where: { $0.episodeNumber == loserEp.episodeNumber }) {
                                    winnerEp.isWatched = true
                                }
                            }
                            tv.seasons.removeAll { $0.persistentModelID == loser.persistentModelID }
                            modelContext.delete(loser) 
                        }
                    }
                    
                    // Heal: Find ALL seasons belonging to this show that might be orphaned
                    let sDescriptor = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID == tmdbID })
                    if let allKnownSeasons = try? modelContext.fetch(sDescriptor) {
                        for season in allKnownSeasons {
                            if season.tvShowDetails?.persistentModelID != tv.persistentModelID {
                                season.tvShowDetails = tv
                            }
                        }
                    }
                    
                    for season in tv.seasons {
                        season.showID = tmdbID
                        if season.uniqueID == nil {
                            season.uniqueID = "\(tmdbID)_\(season.seasonNumber)"
                        }
                        season.tvShowDetails = tv
                        
                        // Deduplicate Episodes within the season
                        let validEpisodes = season.episodes.filter { !$0.isDeleted }
                        let groupedEpisodes = Dictionary(grouping: validEpisodes, by: { $0.episodeNumber })
                        for (num, duplicates) in groupedEpisodes where duplicates.count > 1 {
                            print("🔍 Maintenance: Found \(duplicates.count) duplicate episodes for S\(season.seasonNumber) E\(num)")
                            let sorted = duplicates.sorted { 
                                if $0.isWatched != $1.isWatched { return $0.isWatched }
                                return ($0.airDate ?? "").count > ($1.airDate ?? "").count 
                            }
                            
                            let winner = sorted[0]
                            for i in 1..<sorted.count { 
                                let loser = sorted[i]
                                if loser.isWatched { winner.isWatched = true }
                                season.episodes.removeAll { $0.persistentModelID == loser.persistentModelID }
                                modelContext.delete(loser) 
                            }
                        }

                        // Heal: Find ALL episodes belonging to this season that might be orphaned
                        let sNum = season.seasonNumber
                        let eDescriptor = FetchDescriptor<TVEpisode>(predicate: #Predicate { $0.showID == tmdbID && $0.seasonNumber == sNum })
                        if let allKnownEpisodes = try? modelContext.fetch(eDescriptor) {
                            for episode in allKnownEpisodes where !episode.isDeleted {
                                if episode.season?.persistentModelID != season.persistentModelID {
                                    episode.season = season
                                }
                            }
                        }

                        for episode in season.episodes where !episode.isDeleted {
                            episode.showID = tmdbID
                            if episode.uniqueID == nil {
                                episode.uniqueID = "\(tmdbID)_\(season.seasonNumber)_\(episode.episodeNumber)"
                            }
                            episode.season = season
                        }
                        
                        // Phase 3 Optimization: Populate Persistent Dates
                        for episode in season.episodes where !episode.isDeleted {
                            if episode.airDateValue == nil {
                                episode.updateAirDateValue()
                            }
                        }
                    }
                    
                    // 4. Purge legacy Crew cards, Ensure mediaID, and Deduplicate Cast
                    let validCast = tv.cast.filter { !$0.isDeleted }
                    let groupedCast = Dictionary(grouping: validCast, by: { "\($0.name)|\($0.characterName)" })
                    for (_, duplicates) in groupedCast where duplicates.count > 1 {
                        let sorted = duplicates.sorted { ($0.profileURL != nil ? 1 : 0) > ($1.profileURL != nil ? 1 : 0) }
                        for i in 1..<sorted.count {
                            modelContext.delete(sorted[i])
                        }
                    }

                    for member in tv.cast where !member.isDeleted {
                        member.mediaID = item.id
                        if member.characterName == "Creator" || member.characterName == "Director" {
                            modelContext.delete(member)
                        }
                    }
                    
                    tv.recalculateCachedProperties(triggerSync: true)
                }
                
                if let movie = item.movieDetails {
                    let validCast = movie.cast.filter { !$0.isDeleted }
                    let groupedCast = Dictionary(grouping: validCast, by: { "\($0.name)|\($0.characterName)" })
                    for (_, duplicates) in groupedCast where duplicates.count > 1 {
                        let sorted = duplicates.sorted { ($0.profileURL != nil ? 1 : 0) > ($1.profileURL != nil ? 1 : 0) }
                        for i in 1..<sorted.count {
                            modelContext.delete(sorted[i])
                        }
                    }

                    for member in movie.cast where !member.isDeleted {
                        member.mediaID = item.id
                        if member.characterName == "Director" {
                            modelContext.delete(member)
                        }
                    }
                }
            }
            
            item.syncCachedProperties()
            item.updateSearchableText()
        }
        
        // 3. Final Badge Sync pass and Cache Purge for Logos
        let finalItems = (try? modelContext.fetch(descriptor)) ?? []
        var logoURLs: [String] = []
        for item in finalItems where !item.isDeleted {
            item.syncCachedProperties()
            if let logo = item.cachedNetworkLogoPath, let url = APIClient.tmdbImageURL(path: logo, size: "w300") {
                logoURLs.append(url)
            }
        }
        
        // Asynchronously clear logo cache so they regenerate with proper alpha
        if !logoURLs.isEmpty {
            await ImageCache.shared.clearCache(forURLs: logoURLs)
        }
        
        try? modelContext.save()
        print("✅ Maintenance: Library heal, badge refresh, and logo cache optimization complete.")
    }
}
