import Foundation
import SwiftData
import SwiftUI

struct LibraryBackup: Codable {
    let items: [MediaItemData]
    var version: Int = 1
}

struct MediaItemData: Codable {
    let id: String
    let title: String
    let overview: String
    let posterURL: String?
    let releaseDate: Date?
    let dateAdded: Date?
    let state: String
    let type: String
    let isLiked: Bool?
    let watchHistory: [String: Bool]  // EpisodeID: isWatched
}

/// A background actor for heavy SwiftData operations and throttled networking.
@ModelActor
actor BackgroundDataService {
    private let decoder = JSONDecoder()

    func refreshMetadata(for itemIDs: [PersistentIdentifier]) async {
        // Use withTaskGroup to throttle network requests (max 5 at a time)
        await withTaskGroup(of: Void.self) { group in
            var activeTasks = 0
            
            for id in itemIDs {
                if activeTasks >= 5 {
                    await group.next()
                    activeTasks -= 1
                }
                
                group.addTask {
                    await self.refreshSingleItem(id: id)
                }
                activeTasks += 1
            }
        }
        
        try? modelContext.save()
    }
    
    private func refreshSingleItem(id: PersistentIdentifier) async {
        guard let item = modelContext.model(for: id) as? MediaItem else { return }
        
        do {
            if item.type == .movie, let tmdbID = Int(item.id) {
                let details = try await APIClient.shared.fetchMovieDetails(tmdbID: tmdbID)
                item.releaseDate = DateUtils.parseDate(details.releaseDate)
                let movieDetails = item.movieDetails ?? MovieDetails(tmdbID: tmdbID)
                movieDetails.runtime = details.runtime
                movieDetails.genres = details.genres
                movieDetails.voteAverage = details.voteAverage
                movieDetails.originalLanguage = details.originalLanguage
                movieDetails.creators = details.directors.map { $0.name }

                // Update Cast (Directors First)
                var newCastList: [CastMember] = []
                
                for d in details.directors {
                    let profileURL = d.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(d.profilePath!)" : nil
                    newCastList.append(CastMember(name: d.name, characterName: "Director", profileURL: profileURL, order: -1))
                }
                
                for c in details.cast {
                    let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                    newCastList.append(CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order))
                }
                movieDetails.cast = newCastList

                item.movieDetails = movieDetails
                item.lastUpdated = Date()
                item.updateSearchableText()
                
                // Note: We skip MainActor indexing here for simplicity and safety.
                // In a full implementation, we'd send the ID back to the main actor.
            } else if item.type == .tvShow, let tmdbID = Int(item.id) {
                let details = try await APIClient.shared.fetchTVDetails(tmdbID: tmdbID)
                item.releaseDate = DateUtils.parseDate(details.firstAirDate)
                let tvDetails = item.tvShowDetails ?? TVShowDetails(tmdbID: tmdbID)
                tvDetails.voteAverage = details.voteAverage
                tvDetails.genres = details.genres
                tvDetails.network = details.network
                tvDetails.networkLogoPath = details.networkLogoPath
                tvDetails.originalLanguage = details.originalLanguage
                tvDetails.status = details.status
                tvDetails.numberOfSeasons = details.seasonsCount
                tvDetails.numberOfEpisodes = details.episodesCount
                tvDetails.creators = details.creators.map { $0.name }

                // Update Cast (Creators First)
                var newCastList: [CastMember] = []
                
                for c in details.creators {
                    let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                    newCastList.append(CastMember(name: c.name, characterName: "Creator", profileURL: profileURL, order: -1))
                }
                
                for c in details.cast {
                    let profileURL = c.profilePath != nil ? "https://image.tmdb.org/t/p/w185\(c.profilePath!)" : nil
                    newCastList.append(CastMember(name: c.name, characterName: c.character, profileURL: profileURL, order: c.order))
                }
                tvDetails.cast = newCastList

                for seasonBrief in details.seasons {
                    if let existingSeason = tvDetails.seasons.first(where: { $0.seasonNumber == seasonBrief.season_number }) {
                        existingSeason.name = seasonBrief.name
                        existingSeason.episodeCount = seasonBrief.episode_count
                        existingSeason.airDate = seasonBrief.air_date

                        let epResults = try? await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: seasonBrief.season_number)
                        if let eps = epResults {
                            for epData in eps {
                                if let existingEp = existingSeason.episodes.first(where: { $0.episodeNumber == epData.episodeNumber }) {
                                    existingEp.name = epData.name
                                    existingEp.overview = epData.overview
                                    existingEp.airDate = epData.airDate
                                    existingEp.runtime = epData.runtime
                                } else {
                                    let newEp = TVEpisode(episodeNumber: epData.episodeNumber, seasonNumber: seasonBrief.season_number, name: epData.name, overview: epData.overview, airDate: epData.airDate, runtime: epData.runtime)
                                    existingSeason.episodes.append(newEp)
                                }
                            }
                        }
                    } else {
                        let newSeason = TVSeason(seasonNumber: seasonBrief.season_number, name: seasonBrief.name, episodeCount: seasonBrief.episode_count, airDate: seasonBrief.air_date)
                        let epResults = try? await APIClient.shared.fetchSeasonDetails(tmdbID: tmdbID, seasonNumber: seasonBrief.season_number)
                        if let eps = epResults {
                            newSeason.episodes = eps.map { TVEpisode(episodeNumber: $0.episodeNumber, seasonNumber: seasonBrief.season_number, name: $0.name, overview: $0.overview, airDate: $0.airDate, runtime: $0.runtime) }
                        }
                        tvDetails.seasons.append(newSeason)
                    }
                }

                item.tvShowDetails = tvDetails
                tvDetails.recalculateCachedProperties()
                item.lastUpdated = Date()
                item.updateSearchableText()
            }
        } catch {
            print("❌ Background refresh error: \(error)")
        }
    }
}

@MainActor
class DataService {
    static let shared = DataService()
    
    /// Tracks items refreshed during this app session to avoid redundant network calls.
    private var sessionRefreshedItems = Set<String>()
    
    func hasRefreshedThisSession(id: String) -> Bool {
        return sessionRefreshedItems.contains(id)
    }
    
    func markAsRefreshedThisSession(id: String) {
        sessionRefreshedItems.insert(id)
    }

    func refreshMetadata(for items: [MediaItem], modelContext: ModelContext) {
        let itemIDs = items.map { $0.persistentModelID }
        let backgroundService = BackgroundDataService(modelContainer: modelContext.container)
        
        Task {
            await backgroundService.refreshMetadata(for: itemIDs)
        }
    }

    func exportLibrary(items: [MediaItem]) {
        let backupItems = items.map { item in
            var watchHistory: [String: Bool] = [:]
            if let tv = item.tvShowDetails {
                for season in tv.seasons {
                    for episode in season.episodes {
                        if episode.isWatched {
                            watchHistory["\(season.seasonNumber)_\(episode.episodeNumber)"] = true
                        }
                    }
                }
            }

            return MediaItemData(
                id: item.id,
                title: item.title,
                overview: item.overview,
                posterURL: item.posterURL,
                releaseDate: item.releaseDate,
                dateAdded: item.dateAdded,
                state: item.state?.rawValue ?? "Wishlist",
                type: item.type?.rawValue ?? "Movie",
                isLiked: item.isLiked,
                watchHistory: watchHistory
            )
        }

        let backup = LibraryBackup(items: backupItems)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(backup)
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json]
            savePanel.nameFieldStringValue = "MediaTracker_Backup.json"

            savePanel.begin { result in
                if result == .OK, let url = savePanel.url {
                    try? data.write(to: url)
                }
            }
        } catch {
            print("❌ Export error: \(error)")
        }
    }

    func importLibrary(modelContext: ModelContext) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false

        openPanel.begin { result in
            if result == .OK, let url = openPanel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let backup = try decoder.decode(LibraryBackup.self, from: data)

                    for itemData in backup.items {
                        let descriptor = FetchDescriptor<MediaItem>(predicate: #Predicate { $0.id == itemData.id })
                        let existing = try? modelContext.fetch(descriptor)

                        if let item = existing?.first {
                            item.state = MediaState(rawValue: itemData.state) ?? .wishlist
                            item.isLiked = itemData.isLiked
                            if let importedDate = itemData.dateAdded {
                                item.dateAdded = importedDate
                            }

                            if let tv = item.tvShowDetails {
                                for (key, _) in itemData.watchHistory {
                                    let parts = key.split(separator: "_")
                                    if parts.count == 2, let s = Int(parts[0]), let e = Int(parts[1]) {
                                        if let episode = tv.seasons.first(where: { $0.seasonNumber == s })?.episodes.first(where: { $0.episodeNumber == e }) {
                                            episode.isWatched = true
                                        }
                                    }
                                }
                            }
                            item.updateSearchableText()
                        } else {
                            let item = MediaItem(
                                id: itemData.id,
                                title: itemData.title,
                                overview: itemData.overview,
                                posterURL: itemData.posterURL,
                                releaseDate: itemData.releaseDate,
                                isLiked: itemData.isLiked,
                                state: MediaState(rawValue: itemData.state) ?? .wishlist,
                                type: MediaType(rawValue: itemData.type) ?? .movie
                            )
                            item.dateAdded = itemData.dateAdded ?? Date()
                            
                            if item.type == .tvShow, let tmdbID = Int(item.id) {
                                let tv = TVShowDetails(tmdbID: tmdbID)
                                item.tvShowDetails = tv
                                tv.recalculateCachedProperties()
                            }
                            item.updateSearchableText()
                            modelContext.insert(item)
                        }
                    }
                    try? modelContext.save()
                } catch {
                    print("❌ Import error: \(error)")
                }
            }
        }
    }
}
