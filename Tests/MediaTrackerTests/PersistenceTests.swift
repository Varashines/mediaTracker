import XCTest
import SwiftData
@testable import MediaTracker

final class PersistenceTests: MTTestCase {
    @MainActor
    func testFullSchemaInitializesWithoutError() throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self,
            TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self,
            NetworkEntity.self, GenreEntity.self, LanguageEntity.self,
            BadgeEntity.self, PersonImageEntity.self,
            StudioAliasEntity.self, SearchCacheEntity.self,
            MediaCollection.self, ProviderEntity.self, MediaFacetIndex.self,
            WatchCycle.self, WatchEvent.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        XCTAssertNoThrow(try ModelContainer(for: schema, configurations: [config]),
                         "Full schema should initialize without error — if this fails, a @Model property change broke auto-migration compatibility")
    }
    
    @MainActor
    func testPersistentRepairPreservesValidHistoryAndRemovesOrphans() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self,
            NetworkEntity.self, GenreEntity.self, LanguageEntity.self, BadgeEntity.self,
            PersonImageEntity.self, StudioAliasEntity.self, SearchCacheEntity.self,
            ProviderEntity.self, MediaFacetIndex.self, WatchCycle.self, WatchEvent.self
        ])
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaTracker-Repair-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("repair.store")

        do {
            let container = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, url: storeURL)]
            )
            let context = container.mainContext
            let item = MediaItem(id: "movie_valid", title: "Valid", overview: "", type: .movie)
            context.insert(item)
            let validCycle = WatchCycle(mediaID: item.id, kind: .movie, state: .completed, isComplete: true)
            let orphanCycle = WatchCycle(mediaID: "missing_media", kind: .movie)
            context.insert(validCycle)
            context.insert(orphanCycle)
            context.insert(WatchEvent(cycleID: validCycle.id, mediaID: item.id, watchedAt: Date(), deduplicationKey: "valid"))
            context.insert(WatchEvent(cycleID: orphanCycle.id, mediaID: orphanCycle.mediaID, watchedAt: Date(), deduplicationKey: "orphan"))
            try context.save()
        }

        let versionKey = UserDefaultsKeys.watchHistoryRepairV1.rawValue
        UserDefaults.standard.set(0, forKey: versionKey)
        defer { UserDefaults.standard.removeObject(forKey: versionKey) }

        let repairedContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, url: storeURL)]
        )
        await DatabaseMigrations.runWatchHistoryRepairIfNeeded(container: repairedContainer)

        let context = repairedContainer.mainContext
        XCTAssertEqual(try context.fetch(FetchDescriptor<MediaItem>()).map(\.id), ["movie_valid"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchCycle>()).map(\.mediaID), ["movie_valid"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<WatchEvent>()).map(\.mediaID), ["movie_valid"])
    }

    @MainActor
    func testTVEpisodePersistence() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // 1. Create a TV show
        let item = MediaItem(id: "123", title: "Test Show", overview: "Overview", type: .tvShow)
        context.insert(item)
        
        let tvDetails = TVShowDetails(tmdbID: 123)
        tvDetails.item = item
        item.tvShowDetails = tvDetails
        context.insert(tvDetails)
        
        let season = TVSeason(seasonNumber: 1, name: "Season 1", episodeCount: 10, showID: 123)
        season.tvShowDetails = tvDetails
        tvDetails.seasons.append(season)
        context.insert(season)
        
        try context.save()
        
        // 2. Simulate refresh adding an episode
        let epResult = TVEpisodeResult(episodeNumber: 1, name: "Pilot", overview: "The start", airDate: "2026-05-01", runtime: 45)
        
        let seasonID = season.persistentModelID
        
        // Find the season again on MainActor
        guard let tv = item.tvShowDetails,
              let seasonOnMain = tv.seasons.first(where: { $0.persistentModelID == seasonID }) else {
            XCTFail("Missing season")
            return
        }
        
        let newEpisode = TVEpisode(
            episodeNumber: epResult.episodeNumber,
            seasonNumber: seasonOnMain.seasonNumber,
            name: epResult.name ?? "Unknown",
            overview: epResult.overview ?? "",
            airDate: epResult.airDate ?? "",
            airstamp: nil,
            runtime: epResult.runtime,
            showID: 123
        )
        newEpisode.season = seasonOnMain
        context.insert(newEpisode)
        seasonOnMain.episodes.append(newEpisode)
        
        tv.recalculateCachedProperties()
        item.updateSearchableText()
        
        try context.save()
        
        // 3. Verify persistence
        let descriptor = FetchDescriptor<TVEpisode>()
        let fetchedEpisodes = try context.fetch(descriptor)
        
        XCTAssertEqual(fetchedEpisodes.count, 1, "Episode should be persisted")
        XCTAssertEqual(fetchedEpisodes.first?.name, "Pilot")
        XCTAssertNotNil(fetchedEpisodes.first?.season, "Relationship to season should be preserved")
        
        // 4. Verify back-references
        let fetchedSeasons = try context.fetch(FetchDescriptor<TVSeason>())
        XCTAssertEqual(fetchedSeasons.first?.episodes.count, 1, "Season should have 1 episode")
    }
}
