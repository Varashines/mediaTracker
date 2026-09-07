import XCTest
import SwiftData
@testable import MediaTracker

/// Regression tests for the 9.0.3 background-sync abort:
/// `NSSQLGenerator newSQLStatementForRequest` throwing inside
/// `performLibraryHeal`'s batched season fetch.
///
/// Root cause (verified by crashing probe runs): a nil-coalescing TERNARY as
/// the LHS of an IN test — `set.contains($0.showID ?? 0)` — is untranslatable
/// to SQL and throws an NSException, which Swift cannot catch, aborting the
/// app. The production fetch therefore uses an optional-typed IN list with no
/// coalescing, pinned by `testSetContainsOptional` below.
///
/// NOTE: the aborting shapes (`Set`/`Array` + `contains(optional ?? 0)`) are
/// deliberately NOT kept as tests — on regression they abort the whole test
/// runner instead of failing normally.
///
/// NOTE: the returned container must be held for the test's duration —
/// a bare ModelContext does not retain it, and fetching after the
/// container deallocates traps inside SwiftData.
final class HealPredicateRegressionTests: MTTestCase {
    @MainActor
    private func seedSeasons() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self,
            SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        let item = MediaItem(id: "tv_101", title: "Probe Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: 101)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        let s1 = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10, showID: 101)
        s1.tvShowDetails = tv
        tv.seasons.append(s1)
        context.insert(s1)
        context.insert(TVSeason(seasonNumber: 1, name: "S1", episodeCount: 8, showID: 102))
        context.insert(TVSeason(seasonNumber: 1, name: "S1", episodeCount: 6, showID: nil))
        try context.save()
        return (container, context)
    }

    /// Control: no predicate at all.
    @MainActor
    func testPlainFetch() async throws {
        let seeded = try seedSeasons()
        let fetched = try seeded.1.fetch(FetchDescriptor<TVSeason>())
        XCTAssertEqual(fetched.count, 3)
    }

    /// Control: optional-==-scalar, the shape used all over the codebase.
    @MainActor
    func testOptionalEquality() async throws {
        let seeded = try seedSeasons()
        let id = 101
        let found = try seeded.1.fetch(
            FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID == id })
        )
        XCTAssertEqual(found.count, 1)
    }

    /// The production shape: captured optional-typed Set, no coalescing.
    /// Nil showIDs are excluded by three-valued logic.
    @MainActor
    func testSetContainsOptional() async throws {
        let seeded = try seedSeasons()
        let context = seeded.1
        let batchShowIDs: Set<Int?> = [101, 102]
        let found = try context.fetch(
            FetchDescriptor<TVSeason>(predicate: #Predicate { batchShowIDs.contains($0.showID) })
        )
        XCTAssertEqual(found.count, 2)
    }
}
