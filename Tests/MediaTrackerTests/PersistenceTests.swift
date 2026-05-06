import XCTest
import SwiftData
@testable import MediaTracker

final class PersistenceTests: XCTestCase {
    @MainActor
    func testTVEpisodePersistence() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, CastMember.self, MediaCollection.self
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
