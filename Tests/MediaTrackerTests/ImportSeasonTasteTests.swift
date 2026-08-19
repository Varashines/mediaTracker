import XCTest
import SwiftData
@testable import MediaTracker

@MainActor
final class ImportSeasonTasteTests: XCTestCase {

    private func makeContainer() -> ModelContainer {
        let schema = Schema([
            MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self,
            SeasonCastMember.self, CastMember.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    private func makeShowItem(id: String, tmdbID: Int, context: ModelContext) -> MediaItem {
        let item = MediaItem(id: id, title: "Show", overview: "", type: .tvShow)
        context.insert(item)
        let tv = TVShowDetails(tmdbID: tmdbID)
        tv.item = item
        item.tvShowDetails = tv
        context.insert(tv)
        return item
    }

    func testSeasonTasteOverridesRoundTripThroughBackup() throws {
        let container = makeContainer()
        let context = container.mainContext

        let item = makeShowItem(id: "tv_101", tmdbID: 101, context: context)
        let s1 = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10, showID: 101)
        s1.tasteOverride = .love
        s1.tvShowDetails = item.tvShowDetails
        context.insert(s1)
        let s2 = TVSeason(seasonNumber: 2, name: "S2", episodeCount: 10, showID: 101)
        s2.tasteOverride = .dislike
        s2.tvShowDetails = item.tvShowDetails
        context.insert(s2)
        try context.save()

        let data = MediaItemData(item: item, watchedIDs: nil, watchedDates: nil)
        XCTAssertEqual(data.seasonTasteOverrides, [1: "Love", 2: "Dislike"])

        // Encode / decode through LibraryBackup (uses the custom date decoder).
        let backup = LibraryBackup(items: [data], collections: nil)
        let encoded = try JSONEncoder().encode(backup)
        let decoded = try LibraryBackup.createDecoder().decode(LibraryBackup.self, from: encoded)
        XCTAssertEqual(decoded.items.first?.seasonTasteOverrides, [1: "Love", 2: "Dislike"])
    }

    func testApplySeasonTasteOverridesOnImport() throws {
        let container = makeContainer()
        let context = container.mainContext

        let item = makeShowItem(id: "tv_202", tmdbID: 202, context: context)
        try context.save()

        let data = MediaItemData(
            id: "tv_202", title: "Show", type: "TV Show", state: "Active",
            dateAdded: Date(), taste: "Love", watchedEpisodeIDs: nil,
            lastInteractionDate: nil, watchedEpisodeDates: nil,
            seasonTasteOverrides: [1: "Love", 3: "Dislike"],
            posterURL: nil, overview: nil, backdropURL: nil, releaseDate: nil,
            lastUpdated: nil, titleLogoURL: nil, themeColorHex: nil,
            cachedRuntime: nil, cachedEpisodeRuntime: nil, cachedWatchedEpisodeCount: nil,
            remainingEpisodesCount: nil, cachedLanguage: nil, cachedNetwork: nil,
            cachedNetworkLogoPath: nil, mood: nil
        )

        data.applySeasonTasteOverrides(to: item, in: context)

        let sDesc = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID == 202 })
        let seasons = try context.fetch(sDesc)
        let map = Dictionary(uniqueKeysWithValues: seasons.map { ($0.seasonNumber, $0.tasteOverrideRaw) })
        XCTAssertEqual(map[1], "Love")
        XCTAssertEqual(map[3], "Dislike")
    }

    func testMergeDoesNotOverwriteExistingSeasonTaste() throws {
        let container = makeContainer()
        let context = container.mainContext

        let item = makeShowItem(id: "tv_303", tmdbID: 303, context: context)
        let s1 = TVSeason(seasonNumber: 1, name: "S1", episodeCount: 10, showID: 303)
        s1.tasteOverride = .like   // existing user override
        s1.tvShowDetails = item.tvShowDetails
        context.insert(s1)
        try context.save()

        let data = MediaItemData(
            id: "tv_303", title: "Show", type: "TV Show", state: "Active",
            dateAdded: Date(), taste: "Love", watchedEpisodeIDs: nil,
            lastInteractionDate: nil, watchedEpisodeDates: nil,
            seasonTasteOverrides: [1: "Dislike", 2: "Love"],
            posterURL: nil, overview: nil, backdropURL: nil, releaseDate: nil,
            lastUpdated: nil, titleLogoURL: nil, themeColorHex: nil,
            cachedRuntime: nil, cachedEpisodeRuntime: nil, cachedWatchedEpisodeCount: nil,
            remainingEpisodesCount: nil, cachedLanguage: nil, cachedNetwork: nil,
            cachedNetworkLogoPath: nil, mood: nil
        )

        // Merge semantics: preserve an existing season override.
        data.applySeasonTasteOverrides(to: item, in: context, mergeOnlyIfEmpty: true)

        let sDesc = FetchDescriptor<TVSeason>(predicate: #Predicate { $0.showID == 303 })
        let seasons = try context.fetch(sDesc)
        let map = Dictionary(uniqueKeysWithValues: seasons.map { ($0.seasonNumber, $0.tasteOverrideRaw) })
        XCTAssertEqual(map[1], "Like", "Merge must not clobber an existing override")
        XCTAssertEqual(map[2], "Love", "Missing season should be created with the override")
    }

    func testImportKeyNormalizesLegacyTypeSpellings() {
        XCTAssertEqual(
            MediaItemData.importKey(id: "movie_42", typeRawValue: "movie"),
            "movie_42_Movie"
        )
        XCTAssertEqual(
            MediaItemData.importKey(id: "42", typeRawValue: "Movie"),
            "movie_42_Movie"
        )
        XCTAssertEqual(
            MediaItemData.importKey(id: "tv_42", typeRawValue: "tv"),
            "tv_42_TV Show"
        )
        XCTAssertEqual(
            MediaItemData.importKey(id: "42", typeRawValue: "series"),
            "tv_42_TV Show"
        )
    }

    func testSkipImportRecognizesLowercaseLegacyMovieType() async throws {
        let container = makeContainer()
        let context = container.mainContext
        context.insert(MediaItem(id: "movie_404", title: "Existing", overview: "", type: .movie))
        try context.save()

        let data = MediaItemData(
            id: "404", title: "Legacy", type: "movie", state: "Wishlist",
            dateAdded: Date(), taste: nil, watchedEpisodeIDs: nil,
            lastInteractionDate: nil, watchedEpisodeDates: nil,
            seasonTasteOverrides: nil, posterURL: nil, overview: nil,
            backdropURL: nil, releaseDate: nil, lastUpdated: nil,
            titleLogoURL: nil, themeColorHex: nil, cachedRuntime: nil,
            cachedEpisodeRuntime: nil, cachedWatchedEpisodeCount: nil,
            remainingEpisodesCount: nil, cachedLanguage: nil,
            cachedNetwork: nil, cachedNetworkLogoPath: nil, mood: nil
        )
        let service = BackgroundDataService(modelContainer: container)

        let result = await service.importLibraryData(
            backup: LibraryBackup(items: [data], collections: nil),
            strategy: .skip
        )

        XCTAssertEqual(result.imported, 0)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<MediaItem>()).count, 1)
    }
}
