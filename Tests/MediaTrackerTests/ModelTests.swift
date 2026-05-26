import XCTest
import SwiftData
@testable import MediaTracker

final class GenreMapperTests: XCTestCase {
    func testStandardizeSimpleGenres() {
        let result = GenreMapper.standardize(["Action", "Drama"])
        XCTAssertEqual(result, ["Action", "Drama"])
    }

    func testStandardizeSplitsCompound() {
        let result = GenreMapper.standardize(["Action & Adventure"])
        XCTAssertTrue(result.contains("Action"))
        XCTAssertTrue(result.contains("Adventure"))
    }

    func testStandardizeMapsSciFi() {
        let result = GenreMapper.standardize(["Sci-Fi", "Science Fiction"])
        XCTAssertEqual(result, ["Science Fiction"])
    }

    func testStandardizeSplitsWithAnd() {
        let result = GenreMapper.standardize(["War and Politics"])
        XCTAssertTrue(result.contains("War"))
        XCTAssertTrue(result.contains("Politics"))
    }

    func testStandardizeMapsTVMovie() {
        let result = GenreMapper.standardize(["TV Movie"])
        XCTAssertEqual(result, ["TV Movie"])
    }

    func testStandardizeMapsSoap() {
        let result = GenreMapper.standardize(["Soap"])
        XCTAssertEqual(result, ["Soap Opera"])
    }

    func testStandardizeSlashDelimiter() {
        let result = GenreMapper.standardize(["Sci-Fi & Fantasy"])
        XCTAssertTrue(result.contains("Science Fiction"))
        XCTAssertTrue(result.contains("Fantasy"))
    }

    func testStandardizeEmptyInput() {
        let result = GenreMapper.standardize([])
        XCTAssertTrue(result.isEmpty)
    }

    func testStandardizeDeduplicates() {
        let result = GenreMapper.standardize(["Action", "Action"])
        XCTAssertEqual(result, ["Action"])
    }
}

final class LanguageUtilsTests: XCTestCase {
    func testLanguageNameForNil() {
        XCTAssertEqual(LanguageUtils.languageName(for: nil), "Unknown")
    }

    func testLanguageNameForEmpty() {
        XCTAssertEqual(LanguageUtils.languageName(for: ""), "Unknown")
    }

    func testLanguageNameForEnglish() {
        XCTAssertEqual(LanguageUtils.languageName(for: "en"), "English")
    }

    func testLanguageNameForKnownCode() {
        let name = LanguageUtils.languageName(for: "ja")
        XCTAssertFalse(name.isEmpty)
        XCTAssertNotEqual(name, "Unknown")
    }
}

final class MediaItemComputedPropertiesTests: XCTestCase {
    @MainActor
    func testIsUpcomingTrueForFutureDate() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        item.cachedNextAiringDate = Date().addingTimeInterval(86400)
        context.insert(item)
        try context.save()

        XCTAssertTrue(item.isUpcoming)
    }

    @MainActor
    func testIsUpcomingFalseForPastDate() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        item.cachedNextAiringDate = Date().addingTimeInterval(-86400)
        context.insert(item)
        try context.save()

        XCTAssertFalse(item.isUpcoming)
    }

    func testAvailableStatesForCompleted() {
        let states = MediaItem.availableStates(for: .tvShow, progress: 1.0)
        XCTAssertEqual(states, [.completed, .rewatching])
    }

    func testAvailableStatesForInProgress() {
        let states = MediaItem.availableStates(for: .movie, progress: 0.5)
        XCTAssertEqual(states, [.active, .onHold, .dropped, .rewatching, .completed])
    }

    func testAvailableStatesForWishlist() {
        let states = MediaItem.availableStates(for: .movie, progress: 0)
        XCTAssertEqual(states, MediaState.allCases)
    }

    func testRequiresMaintenanceRefreshTrueForNilLastUpdated() {
        let item = MediaItem(id: "1", title: "Test", overview: "")
        XCTAssertTrue(item.requiresMaintenanceRefresh)
    }

    func testRequiresMaintenanceRefreshFalseForRecentUpdate() {
        let item = MediaItem(id: "1", title: "Test", overview: "")
        item.lastUpdated = Date()
        XCTAssertFalse(item.requiresMaintenanceRefresh)
    }

    func testRequiresMaintenanceRefreshTrueForStale() {
        let item = MediaItem(id: "1", title: "Test", overview: "")
        item.lastUpdated = Date().addingTimeInterval(-31 * 86400)
        XCTAssertTrue(item.requiresMaintenanceRefresh)
    }

    func testDisplayCastReturnsStoredCast() {
        let item = MediaItem(id: "1", title: "Test", overview: "")
        let cast = [SimpleCastMember(id: "1", name: "Actor A", characterName: "Role", profileURL: nil, order: 0)]
        item.storedCast = cast
        XCTAssertEqual(item.displayCast.count, 1)
        XCTAssertEqual(item.displayCast[0].name, "Actor A")
    }

    @MainActor
    func testTypeSetter() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, configurations: config)
        let context = container.mainContext

        let item = MediaItem(id: "1", title: "Test", overview: "", type: .movie)
        context.insert(item)
        try context.save()

        XCTAssertEqual(item.type, .movie)
        item.type = .tvShow
        XCTAssertEqual(item.type, .tvShow)
        XCTAssertEqual(item.typeValue, "TV Show")
    }
}

final class SmartRulesTests: XCTestCase {
    func testSmartRuleCodableRoundTrip() throws {
        let rules: [SmartRule] = [
            .genre("Action"),
            .releaseYear(2020, .after),
            .releaseYearRange(1990, 2000),
            .mediaType(.movie),
            .state(.completed),
            .taste(.love),
            .badge("NEW")
        ]

        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([SmartRule].self, from: data)

        XCTAssertEqual(decoded.count, 7)
        XCTAssertEqual(decoded[0], .genre("Action"))
        XCTAssertEqual(decoded[1], .releaseYear(2020, .after))
        XCTAssertEqual(decoded[2], .releaseYearRange(1990, 2000))
        XCTAssertEqual(decoded[3], .mediaType(.movie))
        XCTAssertEqual(decoded[4], .state(.completed))
        XCTAssertEqual(decoded[5], .taste(.love))
        XCTAssertEqual(decoded[6], .badge("NEW"))
    }

    func testSmartRuleComparisonRawValues() {
        XCTAssertEqual(SmartRule.Comparison.equals.rawValue, "is")
        XCTAssertEqual(SmartRule.Comparison.after.rawValue, "after")
        XCTAssertEqual(SmartRule.Comparison.before.rawValue, "before")
    }
}

final class MediaCollectionTests: XCTestCase {
    @MainActor
    func testMediaCollectionInit() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, MediaCollection.self, configurations: config)
        let context = container.mainContext

        let collection = MediaCollection(name: "Favorites", systemImage: "heart.fill", isSmart: false)
        context.insert(collection)
        try context.save()

        XCTAssertEqual(collection.name, "Favorites")
        XCTAssertEqual(collection.systemImage, "heart.fill")
        XCTAssertFalse(collection.isSmart)
        XCTAssertTrue(collection.smartRules.isEmpty)
    }

    @MainActor
    func testSmartCollectionHasRulesData() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, MediaCollection.self, configurations: config)
        let context = container.mainContext

        let collection = MediaCollection(name: "Smart", systemImage: "sparkles", isSmart: true)
        context.insert(collection)
        try context.save()

        XCTAssertTrue(collection.isSmart)
        XCTAssertNotNil(collection.smartRulesData)
    }

    @MainActor
    func testSmartRulesRoundTrip() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: MediaItem.self, MediaCollection.self, configurations: config)
        let context = container.mainContext

        let collection = MediaCollection(name: "Smart", systemImage: "sparkles", isSmart: true)
        collection.smartRules = [.genre("Action"), .mediaType(.movie)]
        context.insert(collection)
        try context.save()

        XCTAssertEqual(collection.smartRules.count, 2)
        XCTAssertEqual(collection.smartRules[0], .genre("Action"))
    }
}

final class MediaStateTests: XCTestCase {
    func testMediaStateDisplayNames() {
        XCTAssertEqual(MediaState.wishlist.displayName, "Watchlist")
        XCTAssertEqual(MediaState.active.displayName, "In Progress")
        XCTAssertEqual(MediaState.completed.displayName, "Completed")
    }

    func testMediaStateIcons() {
        XCTAssertEqual(MediaState.wishlist.iconName, "clock.fill")
        XCTAssertEqual(MediaState.active.iconName, "play.circle.fill")
        XCTAssertEqual(MediaState.completed.iconName, "checkmark.circle.fill")
    }

    func testTasteValueIcons() {
        XCTAssertEqual(TasteValue.love.iconName, "heart.fill")
        XCTAssertEqual(TasteValue.like.iconName, "hand.thumbsup.fill")
        XCTAssertEqual(TasteValue.dislike.iconName, "hand.thumbsdown.fill")
    }

    func testNavigationCategoryTitles() {
        XCTAssertEqual(NavigationCategory.home.title, "Home")
        XCTAssertEqual(NavigationCategory.all.title, "Library")
        XCTAssertEqual(NavigationCategory.movie.title, "Movies")
        XCTAssertEqual(NavigationCategory.tvShow.title, "TV Shows")
        XCTAssertEqual(NavigationCategory.discover.title, "Discovery Hub")
        XCTAssertEqual(NavigationCategory.insights.title, "Cinema DNA")
    }

    func testSmartCategoryDetection() {
        XCTAssertTrue(NavigationCategory.releaseRadar.isSmartCategory)
        XCTAssertTrue(NavigationCategory.smartUpcoming.isSmartCategory)
        XCTAssertTrue(NavigationCategory.catchUp.isSmartCategory)
        XCTAssertTrue(NavigationCategory.loved.isSmartCategory)
        XCTAssertFalse(NavigationCategory.home.isSmartCategory)
        XCTAssertFalse(NavigationCategory.all.isSmartCategory)
        XCTAssertFalse(NavigationCategory.movie.isSmartCategory)
    }

    func testSortOrderIcons() {
        XCTAssertEqual(SortOrder.alphabetical.icon, "textformat.abc")
        XCTAssertEqual(SortOrder.newestRelease.icon, "calendar")
        XCTAssertEqual(SortOrder.recentlyAdded.icon, "clock.badge.checkmark")
    }

    func testMediaTypePluralName() {
        XCTAssertEqual(MediaType.movie.pluralName, "Movies")
        XCTAssertEqual(MediaType.tvShow.pluralName, "TV Shows")
    }
}
