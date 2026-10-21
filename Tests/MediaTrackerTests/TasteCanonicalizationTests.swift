import XCTest
import SwiftData
@testable import MediaTracker

/// Android used to write and push "Loved"/"Liked"/"Disliked" while `TasteValue` only knows
/// "Love"/"Like"/"Dislike", so a rating set on the phone parsed as `nil` here and every
/// taste-driven feature (badge gating, the Loved filters, affinity, insights) ignored it.
/// These tests pin the tolerant parse and the one-off heal that rewrites stored values.
final class TasteCanonicalizationTests: XCTestCase {

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.tasteCanonicalizationV1.rawValue)
        super.tearDown()
    }

    // MARK: - Parsing

    func testTolerantParseAcceptsLegacySpellings() {
        XCTAssertEqual(TasteValue(stored: "Loved"), .love)
        XCTAssertEqual(TasteValue(stored: "Liked"), .like)
        XCTAssertEqual(TasteValue(stored: "Disliked"), .dislike)
    }

    func testTolerantParseIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(TasteValue(stored: "loved"), .love)
        XCTAssertEqual(TasteValue(stored: "LOVE"), .love)
        XCTAssertEqual(TasteValue(stored: "  Like  "), .like)
    }

    func testTolerantParseAcceptsCanonicalAndRejectsJunk() {
        XCTAssertEqual(TasteValue(stored: "Love"), .love)
        XCTAssertEqual(TasteValue(stored: "Like"), .like)
        XCTAssertEqual(TasteValue(stored: "Dislike"), .dislike)
        XCTAssertEqual(TasteValue(stored: "None"), .none)
        XCTAssertEqual(TasteValue(stored: nil), .none)
        XCTAssertEqual(TasteValue(stored: ""), .none)
        XCTAssertEqual(TasteValue(stored: "Favourite"), .none)
    }

    func testCanonicalRawReturnsStorableValue() {
        XCTAssertEqual(TasteValue.canonicalRaw("Loved"), "Love")
        XCTAssertEqual(TasteValue.canonicalRaw("Liked"), "Like")
        XCTAssertEqual(TasteValue.canonicalRaw("Disliked"), "Dislike")
        XCTAssertEqual(TasteValue.canonicalRaw("Love"), "Love")
        XCTAssertEqual(TasteValue.canonicalRaw(nil), "None")
    }

    func testIsLikedOrLovedCoversBothSpellings() {
        XCTAssertTrue(TasteValue(stored: "Loved").isLikedOrLoved)
        XCTAssertTrue(TasteValue(stored: "Like").isLikedOrLoved)
        XCTAssertFalse(TasteValue(stored: "Disliked").isLikedOrLoved)
        XCTAssertFalse(TasteValue(stored: "None").isLikedOrLoved)
    }

    /// The regression that started this: a rating set on Android made the Mac's `taste` nil.
    func testItemTasteReadsLegacyStoredValue() {
        let item = MediaItem(id: "movie_1", title: "T", overview: "", type: .movie)
        item.tasteValue = "Loved"
        XCTAssertEqual(item.taste, .love)

        item.tasteValue = "Disliked"
        XCTAssertEqual(item.taste, .dislike)

        item.tasteValue = "Favourite"
        XCTAssertEqual(item.taste, TasteValue.none, "unknown values read as unrated, never nil")
    }

    // MARK: - Migration

    @MainActor
    func testMigrationRewritesLegacyValuesAndLeavesCanonicalRowsAlone() async throws {
        let container = try ModelContainer(
            for: Schema([MediaItem.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let legacy = MediaItem(id: "movie_legacy", title: "Legacy", overview: "", type: .movie)
        legacy.tasteValue = "Loved"
        let canonical = MediaItem(id: "movie_canonical", title: "Canonical", overview: "", type: .movie)
        canonical.tasteValue = "Dislike"
        context.insert(legacy)
        context.insert(canonical)
        try context.save()

        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.tasteCanonicalizationV1.rawValue)
        await DatabaseMigrations.runTasteCanonicalizationIfNeeded(container: container)

        // Re-fetch rather than reading the main-context objects: the pass writes through its own
        // context, so those instances are stale.
        let verify = ModelContext(container)
        let stored = try verify.fetch(FetchDescriptor<MediaItem>())
        let byID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.tasteValue) })
        XCTAssertEqual(byID["movie_legacy"], "Love")
        XCTAssertEqual(byID["movie_canonical"], "Dislike")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: UserDefaultsKeys.tasteCanonicalizationV1.rawValue))
    }

    @MainActor
    func testMigrationIsGatedByItsVersionFlag() async throws {
        let container = try ModelContainer(
            for: Schema([MediaItem.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let item = MediaItem(id: "movie_gated", title: "Gated", overview: "", type: .movie)
        item.tasteValue = "Liked"
        context.insert(item)
        try context.save()

        // Gate already set: the pass must not run.
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.tasteCanonicalizationV1.rawValue)
        await DatabaseMigrations.runTasteCanonicalizationIfNeeded(container: container)

        let verify = ModelContext(container)
        let stored = try verify.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(stored.first?.tasteValue, "Liked")
    }
}
