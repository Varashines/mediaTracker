import XCTest
import SwiftData
@testable import MediaTracker

/// Regression tests for `mergeSeasonCast`, exercised end-to-end through the
/// public `refreshSeasonCast(tmdbID:seasonNumber:)` with a stubbed shared
/// APIClient session (DEBUG-only hook, restored afterwards).
final class SeasonCastMergeTests: XCTestCase {

    private let tmdbID = 501
    private let seasonNumber = 1

    override func setUp() {
        super.setUp()
        // tmdbURL throws without an API key; NetworkingTests uses the same stub.
        UserDefaults.standard.set("fake_tmdb_key", forKey: "tmdb_api_key")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "tmdb_api_key")
        super.tearDown()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            TVEpisode.self, SeasonCastMember.self, CastMember.self,
            PersonImageEntity.self, MediaCollection.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Aggregate-credits payload with two members: Alice (10 eps) and Carol (5 eps).
    private static let creditsJSON = """
    {
        "cast": [
            {"id": 100, "name": "Alice", "roles": [{"character": "Detective", "episode_count": 10}],
             "profile_path": "/alice.jpg", "order": 0, "total_episode_count": 10},
            {"id": 300, "name": "Carol", "roles": [{"character": "Mayor", "episode_count": 5}],
             "profile_path": null, "order": 2, "total_episode_count": 5}
        ]
    }
    """

    @MainActor
    private func seedShow(in context: ModelContext) throws -> TVSeason {
        let item = MediaItem(id: "tv_\(tmdbID)", title: "Merge Show", overview: "", type: .tvShow)
        context.insert(item)

        let tv = TVShowDetails(tmdbID: tmdbID)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)

        let season = TVSeason(seasonNumber: seasonNumber, name: "S1", episodeCount: 10, showID: tmdbID)
        season.uniqueID = "\(tmdbID)_\(seasonNumber)"
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        // Pre-existing cast member Bob who will be absent from the incoming payload.
        let bob = SeasonCastMember(
            seasonNumber: seasonNumber, tmdbPersonID: 200, name: "Bob",
            characterName: "Old Role", profileURL: nil, episodeCount: 3, order: 9, showID: tmdbID
        )
        bob.uniqueID = "\(tmdbID)_\(seasonNumber)_200"
        bob.season = season
        season.seasonCast.append(bob)
        context.insert(bob)

        try context.save()
        return season
    }

    @MainActor
    func testInsertUpdateDeleteSemantics() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        try seedShow(in: context)

        // Stub APIClient.shared so fetchSeasonAggregateCredits serves our payload.
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [MockURLProtocol.self]
        await APIClient.shared.configureForTesting(session: URLSession(configuration: sessionConfig))
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(url: URL(string: "https://api.themoviedb.org/3")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Self.creditsJSON.data(using: .utf8))
        }
        TasteActor.clearCache()

        let service = BackgroundDataService(modelContainer: container)
        await service.refreshSeasonCast(tmdbID: tmdbID, seasonNumber: seasonNumber)

        let members = try context.fetch(FetchDescriptor<SeasonCastMember>())
        let names = Set(members.map(\.name))

        // Restore the shared client session before asserting so it happens even
        // if an assertion above had thrown.
        await APIClient.shared.configureForTesting(session: URLSession(configuration: .ephemeral))
        MockURLProtocol.requestHandler = nil

        // Delete: Bob was absent from the incoming payload.
        XCTAssertFalse(names.contains("Bob"), "Members absent from the incoming credits should be deleted")

        // Insert: Carol is new and gets a stable uniqueID.
        let carol = members.first(where: { $0.name == "Carol" })
        XCTAssertNotNil(carol, "New credit should be inserted")
        XCTAssertEqual(carol?.uniqueID, "\(tmdbID)_\(seasonNumber)_300")
        XCTAssertEqual(carol?.episodeCount, 5)
        XCTAssertEqual(carol?.seasonNumber, seasonNumber)
        XCTAssertEqual(carol?.showID, tmdbID)

        // Field mapping from aggregate roles.
        let alice = members.first(where: { $0.name == "Alice" })
        XCTAssertEqual(alice?.uniqueID, "\(tmdbID)_\(seasonNumber)_100")
        XCTAssertEqual(alice?.characterName, "Detective")
        XCTAssertEqual(alice?.episodeCount, 10)
        XCTAssertEqual(alice?.order, 0)
        XCTAssertEqual(alice?.tmdbPersonID, 100)
    }
}
