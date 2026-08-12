import XCTest
import SwiftData
@testable import MediaTracker

@MainActor
final class SeasonTasteTests: XCTestCase {

    private func makeContainer() -> ModelContainer {
        let schema = Schema([
            MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
            SeasonCastMember.self, CastMember.self, PersonImageEntity.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Title weight tiers

    func testTitleWeightTiers() {
        XCTAssertEqual(TasteMath.titleWeight(seasonCount: 0), 1)
        XCTAssertEqual(TasteMath.titleWeight(seasonCount: 2), 1)
        XCTAssertEqual(TasteMath.titleWeight(seasonCount: 3), 2)
        XCTAssertEqual(TasteMath.titleWeight(seasonCount: 6), 2)
        XCTAssertEqual(TasteMath.titleWeight(seasonCount: 7), 3)
        XCTAssertEqual(TasteMath.titleWeight(seasonCount: 12), 3)
    }

    // MARK: - Season weight

    func testSeasonWeight() {
        XCTAssertEqual(TasteMath.seasonWeight(TasteValue.love.rawValue), 2)
        XCTAssertEqual(TasteMath.seasonWeight(TasteValue.like.rawValue), 1)
        XCTAssertEqual(TasteMath.seasonWeight(TasteValue.dislike.rawValue), TasteMath.dislikedSeasonWeight)
        XCTAssertEqual(TasteMath.seasonWeight(TasteValue.none.rawValue), 0)
        XCTAssertEqual(TasteMath.seasonWeight(nil), 0)
    }

    // MARK: - "Counts a season" floor

    func testQualifiesFloor() {
        // 10-episode season -> floor min(2, 1.0) = 1.0 -> keep episodeCount > 1 (>=2)
        let s10 = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10, showID: 1)
        let a = SeasonCastMember(seasonNumber: 1, tmdbPersonID: 1, name: "A", characterName: "A", episodeCount: 10, showID: 1)
        a.season = s10
        XCTAssertTrue(a.qualifiesForTaste)
        let cameo10 = SeasonCastMember(seasonNumber: 1, tmdbPersonID: 2, name: "B", characterName: "B", episodeCount: 1, showID: 1)
        cameo10.season = s10
        XCTAssertFalse(cameo10.qualifiesForTaste)

        // 26-episode season -> floor min(2, 2.6) = 2 -> keep episodeCount > 2 (>=3)
        let s26 = TVSeason(seasonNumber: 2, name: "S2", episodeCount: 26, showID: 1)
        let twoEp = SeasonCastMember(seasonNumber: 2, tmdbPersonID: 3, name: "C", characterName: "C", episodeCount: 2, showID: 1)
        twoEp.season = s26
        XCTAssertFalse(twoEp.qualifiesForTaste)
        let threeEp = SeasonCastMember(seasonNumber: 2, tmdbPersonID: 4, name: "D", characterName: "D", episodeCount: 3, showID: 1)
        threeEp.season = s26
        XCTAssertTrue(threeEp.qualifiesForTaste)

        // Short season (<10 eps) keeps one-episode cameos
        let s6 = TVSeason(seasonNumber: 3, name: "S3", episodeCount: 6, showID: 1)
        let oneEp = SeasonCastMember(seasonNumber: 3, tmdbPersonID: 5, name: "E", characterName: "E", episodeCount: 1, showID: 1)
        oneEp.season = s6
        XCTAssertTrue(oneEp.qualifiesForTaste)
    }

    // MARK: - Per-season cast affinity (end-to-end)

    func testCastAffinitySumAcrossSeasons() async throws {
        let container = makeContainer()
        let context = container.mainContext

        let item = MediaItem(id: "tv_101", title: "Show", overview: "", type: .tvShow)
        item.tasteValue = TasteValue.love.rawValue
        item.cachedSeasonCount = 3
        context.insert(item)

        let tv = TVShowDetails(tmdbID: 101)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)

        var seasons: [TVSeason] = []
        let tasteBySeason: [Int: TasteValue] = [1: .love, 2: .like, 3: .dislike]
        for (num, taste) in tasteBySeason {
            let season = TVSeason(seasonNumber: num, name: "S\(num)", episodeCount: 10, showID: 101)
            season.tasteOverride = taste
            season.tvShowDetails = tv
            tv.seasons.append(season)
            context.insert(season)
            seasons.append(season)
        }

        // Alice in all 3 qualifying seasons -> 2 (love) + 1 (like) + 0 (dislike) = 3
        for season in seasons {
            let member = SeasonCastMember(seasonNumber: season.seasonNumber, tmdbPersonID: 100, name: "Alice", characterName: "A", episodeCount: 10, showID: 101)
            member.season = season
            season.seasonCast.append(member)
            context.insert(member)
        }

        // Bob: one-episode cameo in S1 -> excluded by the floor
        if let bobSeason = seasons.first(where: { $0.seasonNumber == 1 }) {
            let bob = SeasonCastMember(seasonNumber: 1, tmdbPersonID: 200, name: "Bob", characterName: "B", episodeCount: 1, showID: 101)
            bob.season = bobSeason
            bobSeason.seasonCast.append(bob)
            context.insert(bob)
        }

        try context.save()

        TasteActor.clearCache()
        let actor = TasteActor(modelContainer: container)
        let insights = await actor.fetchTasteInsights()

        let alice = insights.castAffinities.first { $0.name == "Alice" }
        let bobResult = insights.castAffinities.first { $0.name == "Bob" }

        XCTAssertEqual(alice?.affinity, 3.0, "Alice should sum 2(love)+1(like)+0(dislike) = 3")
        XCTAssertNil(bobResult, "Bob (1-episode cameo) should be excluded by the floor")
    }

    func testSeasonOverrideChangesCastAffinity() async throws {
        let container = makeContainer()
        let context = container.mainContext

        let item = MediaItem(id: "tv_202", title: "Show", overview: "", type: .tvShow)
        item.tasteValue = TasteValue.love.rawValue
        item.cachedSeasonCount = 1
        context.insert(item)

        let tv = TVShowDetails(tmdbID: 202)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)

        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10, showID: 202)
        season.tvShowDetails = tv
        season.watchedEpisodesCount = 10
        tv.seasons.append(season)
        context.insert(season)

        let member = SeasonCastMember(seasonNumber: 1, tmdbPersonID: 100, name: "Alice", characterName: "A", episodeCount: 10, showID: 202)
        member.season = season
        season.seasonCast.append(member)
        context.insert(member)

        try context.save()

        // Show loved -> Alice gets 2. Then override the season to dislike -> 0.
        TasteActor.clearCache()
        let actor = TasteActor(modelContainer: container)
        let before = await actor.fetchTasteInsights()
        XCTAssertEqual(before.castAffinities.first { $0.name == "Alice" }?.affinity, 2.0)

        season.tasteOverride = .dislike
        try context.save()

        TasteActor.clearCache()
        let after = await actor.fetchTasteInsights()
        XCTAssertEqual(after.castAffinities.first { $0.name == "Alice" }?.affinity ?? 0, 0.0)
    }

    func testUnwatchedSeasonDoesNotInheritShowTaste() async throws {
        let container = makeContainer()
        let context = container.mainContext

        let item = MediaItem(id: "tv_303", title: "Show", overview: "", type: .tvShow)
        item.tasteValue = TasteValue.love.rawValue
        item.cachedSeasonCount = 1
        context.insert(item)

        let tv = TVShowDetails(tmdbID: 303)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)

        // Season left unwatched -> should NOT inherit the show's loved taste.
        let season = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10, showID: 303)
        season.tvShowDetails = tv
        tv.seasons.append(season)
        context.insert(season)

        let member = SeasonCastMember(seasonNumber: 1, tmdbPersonID: 100, name: "Alice", characterName: "A", episodeCount: 10, showID: 303)
        member.season = season
        season.seasonCast.append(member)
        context.insert(member)

        try context.save()

        TasteActor.clearCache()
        let actor = TasteActor(modelContainer: container)
        let insights = await actor.fetchTasteInsights()
        XCTAssertNil(insights.castAffinities.first { $0.name == "Alice" },
                     "Unwatched season should not inherit the show's loved taste")
    }
}
