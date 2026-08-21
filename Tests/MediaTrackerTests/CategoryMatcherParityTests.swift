import XCTest
import SwiftData
@testable import MediaTracker

/// Parity tests between `MediaCategoryMatcher` (in-memory semantics) and
/// `MediaFilterPredicates.buildFilteredPredicate` (database semantics),
/// plus smart-rule parity between `countItems` and `filterAndSort`.
@MainActor
final class CategoryMatcherParityTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var actor: MediaFilterActor!

    override func setUpWithError() throws {
        let schema = Schema([MediaItem.self, MovieDetails.self, TVShowDetails.self, TVSeason.self, SeasonCastMember.self, TVEpisode.self, CastMember.self, MediaCollection.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = container.mainContext
        actor = MediaFilterActor(modelContainer: container)
    }

    private func insert(_ id: String, configure: (MediaItem) -> Void) {
        let item = MediaItem(id: id, title: id, overview: "", type: .tvShow)
        configure(item)
        context.insert(item)
        // syncCachedProperties recomputes storedIsUpcoming from air dates —
        // capture the intended flag and restore it after syncing.
        let intendedUpcoming = item.storedIsUpcoming
        item.syncCachedProperties()
        item.storedIsUpcoming = intendedUpcoming
    }

    func testInProgressExcludesUpcomingActiveItems() async throws {
        insert("active") { $0.stateValue = "Active"; $0.storedIsUpcoming = false }
        insert("upcomingActive") { $0.stateValue = "Active"; $0.storedIsUpcoming = true }
        try context.save()

        let result = try await actor.filterAndSort(category: .inProgress, searchText: "", sortOrder: .alphabetical, network: nil, language: nil)
        XCTAssertEqual(Set(result.displayed.map(\.itemID)), ["active"], "Upcoming active items must not appear in .inProgress")

        let viaPredicate = try context.fetch(FetchDescriptor<MediaItem>(predicate: MediaFilterPredicates.buildFilteredPredicate(category: .inProgress, searchToken: "", stateValue: nil, badge: nil, language: nil)))
        XCTAssertEqual(Set(viaPredicate.map(\.id)), ["active"], "Predicate path must agree with matcher")
    }

    func testMatcherMatchesPredicateForStateCategories() throws {
        insert("wishlist") { $0.stateValue = "Wishlist"; $0.storedIsUpcoming = false }
        insert("wishlistUpcoming") { $0.stateValue = "Wishlist"; $0.storedIsUpcoming = true }
        insert("completed") { $0.stateValue = "Completed" }
        insert("onHold") { $0.stateValue = "On Hold" }
        insert("dropped") { $0.stateValue = "Dropped" }
        insert("loved") { $0.stateValue = "Active"; $0.tasteValue = "Love" }
        insert("disliked") { $0.stateValue = "Active"; $0.tasteValue = "Dislike" }
        insert("movie") { $0.typeValue = "Movie" }
        insert("deleted") { $0.stateValue = "Active"; $0.isSoftDeleted = true }
        try context.save()

        let all = try context.fetch(FetchDescriptor<MediaItem>())
        for category in [NavigationCategory.watchlist, .completed, .archive, .loved, .disliked, .movie, .tvShow, .all] {
            let matcherIDs = Set(all.filter { MediaCategoryMatcher.matches($0, category: category) }.map { $0.id })
            let predicateIDs = Set(try context.fetch(FetchDescriptor<MediaItem>(predicate: MediaFilterPredicates.buildFilteredPredicate(category: category, searchToken: "", stateValue: nil, badge: nil, language: nil))).map { $0.id })
            XCTAssertEqual(matcherIDs, predicateIDs, "Matcher/predicate drift for \(category.rawValue)")
        }

        // Soft-deleted items never match any category through the matcher
        XCTAssertTrue(all.filter { $0.isSoftDeleted }.allSatisfy { !MediaCategoryMatcher.matches($0, category: .all) })
    }

    func testSmartRuleParityBetweenCountAndFilter() async throws {
        insert("oldMovie") { $0.typeValue = "Movie"; $0.releaseDate = Date(timeIntervalSinceNow: -10 * 365 * 86400) }
        insert("newMovie") { $0.typeValue = "Movie"; $0.releaseDate = Date() }
        insert("oldShow") { $0.typeValue = "TV Show"; $0.releaseDate = Date(timeIntervalSinceNow: -10 * 365 * 86400) }
        try context.save()

        let collection = MediaCollection(name: "Old Media", systemImage: "clock", isSmart: true)
        collection.smartRules = [.releaseYear(2016, .before)]
        context.insert(collection)
        try context.save()

        let count = try await actor.countItems(category: .all, collectionID: collection.id)
        let result = try await actor.filterAndSort(category: .all, searchText: "", sortOrder: .alphabetical, network: nil, language: nil, collectionID: collection.id)
        XCTAssertEqual(count, result.totalCount, "Smart-rule evaluation must be identical for counting and display")

        // Single-item incremental path must agree too
        for item in try context.fetch(FetchDescriptor<MediaItem>()) {
            let metadata = try await actor.fetchMetadataIfMatches(for: item.persistentModelID, category: .all, searchText: "", collectionID: collection.id)
            XCTAssertEqual(metadata != nil, result.displayed.contains(where: { $0.itemID == item.id }), "Incremental match drift for \(item.id)")
        }
    }
}
