import XCTest
import SwiftData
@testable import MediaTracker

final class ScopedStatsActorTests: MTTestCase {
    @MainActor
    func testNetworkScopeTotalsUseOnlyMatchingItems() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self,
            TVSeason.self, SeasonCastMember.self, TVEpisode.self,
            CastMember.self, MediaCollection.self, StudioAliasEntity.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let firstMatch = MediaItem(id: "scoped-hbo-1", title: "First HBO Match", overview: "", type: .movie)
        firstMatch.cachedNetwork = "HBO"
        firstMatch.cachedRuntime = 100
        firstMatch.cachedWatchProviders = ["Max"]

        let secondMatch = MediaItem(id: "scoped-hbo-2", title: "Second HBO Match", overview: "", type: .movie)
        secondMatch.cachedNetwork = "HBO, Warner TV"
        secondMatch.cachedRuntime = 80
        secondMatch.cachedWatchProviders = ["Max"]

        let nonMatch = MediaItem(id: "scoped-other-1", title: "Other Network", overview: "", type: .movie)
        nonMatch.cachedNetwork = "Netflix"
        nonMatch.cachedRuntime = 120
        nonMatch.cachedWatchProviders = ["Netflix"]

        context.insert(firstMatch)
        context.insert(secondMatch)
        context.insert(nonMatch)
        try context.save()

        let actor = ScopedStatsActor(modelContainer: container)
        let filter = DiscoveryFilter(type: .network, name: "HBO", sourceNames: ["HBO"])
        let stats = await actor.fetchScopedStats(filter: filter, sections: [.providers])

        XCTAssertEqual(stats.totalItems, 2)
        XCTAssertEqual(stats.totalRuntime, 180)
        XCTAssertEqual(stats.topProviders.map(\.name), ["Max"])
        XCTAssertTrue(stats.topActors.isEmpty)
        XCTAssertTrue(stats.topGenres.isEmpty)
        XCTAssertTrue(stats.topNetworks.isEmpty)
        XCTAssertTrue(stats.topLanguages.isEmpty)
    }

    func testVisibleSectionsExcludeTheSelectedFilterCategory() {
        XCTAssertFalse(ScopedStatsSections.visibleSections(for: .genre).contains(.genres))
        XCTAssertFalse(ScopedStatsSections.visibleSections(for: .network).contains(.networks))
        XCTAssertFalse(ScopedStatsSections.visibleSections(for: .studio).contains(.networks))
        XCTAssertFalse(ScopedStatsSections.visibleSections(for: .provider).contains(.providers))
        XCTAssertFalse(ScopedStatsSections.visibleSections(for: .language).contains(.languages))
        XCTAssertEqual(ScopedStatsSections.visibleSections(for: .badge), .all)
    }

    /// Network scope now reads the facet index instead of scanning the library.
    /// The indexed path must return exactly what the broad-scan fallback did.
    @MainActor
    func testNetworkScopeFacetIndexMatchesFallbackTotals() async throws {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self,
            TVSeason.self, SeasonCastMember.self, TVEpisode.self,
            CastMember.self, MediaCollection.self, StudioAliasEntity.self,
            MediaFacetIndex.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let firstMatch = MediaItem(id: "indexed-hbo-1", title: "First HBO Match", overview: "", type: .movie)
        firstMatch.cachedNetwork = "HBO"
        firstMatch.cachedRuntime = 100
        firstMatch.cachedWatchProviders = ["Max"]

        let secondMatch = MediaItem(id: "indexed-hbo-2", title: "Second HBO Match", overview: "", type: .movie)
        secondMatch.cachedNetwork = "HBO, Warner TV"
        secondMatch.cachedRuntime = 80
        secondMatch.cachedWatchProviders = ["Max"]

        let nonMatch = MediaItem(id: "indexed-other-1", title: "Other Network", overview: "", type: .movie)
        nonMatch.cachedNetwork = "Netflix"
        nonMatch.cachedRuntime = 120
        nonMatch.cachedWatchProviders = ["Netflix"]

        for item in [firstMatch, secondMatch, nonMatch] { context.insert(item) }
        for itemID in ["indexed-hbo-1", "indexed-hbo-2"] {
            context.insert(MediaFacetIndex(mediaItemID: itemID, kind: .network, key: "hbo"))
        }
        context.insert(MediaFacetIndex(mediaItemID: "indexed-other-1", kind: .network, key: "netflix"))
        try context.save()

        let actor = ScopedStatsActor(modelContainer: container)
        let filter = DiscoveryFilter(type: .network, name: "HBO", sourceNames: ["HBO"])
        let stats = await actor.fetchScopedStats(filter: filter, sections: [.providers])

        XCTAssertEqual(stats.totalItems, 2)
        XCTAssertEqual(stats.totalRuntime, 180)
        XCTAssertEqual(stats.topProviders.map(\.name), ["Max"])
    }
}
