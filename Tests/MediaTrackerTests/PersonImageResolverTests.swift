import XCTest
import SwiftData
@testable import MediaTracker

/// Regression tests for `PersonImageResolver` (shared by TasteActor and
/// LibraryStatsActor): cache hit, CastMember fallback with write-back, and nil.
final class PersonImageResolverTests: MTTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([PersonImageEntity.self, CastMember.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    func testReturnsCachedEntityWithoutWriteBack() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PersonImageEntity(name: "Alice", profileURL: "/cached.jpg"))
        try context.save()

        let resolved = PersonImageResolver.resolve(for: "Alice", in: context)

        XCTAssertEqual(resolved, "/cached.jpg")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersonImageEntity>()).count, 1, "Cache hit should not insert a duplicate entity")
    }

    @MainActor
    func testFallsBackToCastMemberAndWritesBackCache() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(CastMember(name: "Bob", characterName: "Sidekick", profileURL: "/bob.jpg"))
        try context.save()

        let resolved = PersonImageResolver.resolve(for: "Bob", in: context)

        XCTAssertEqual(resolved, "/bob.jpg", "Should fall back to the CastMember profile URL")
        let cached = try context.fetch(FetchDescriptor<PersonImageEntity>(predicate: #Predicate { $0.name == "Bob" }))
        XCTAssertEqual(cached.count, 1, "Fallback should write back a PersonImageEntity cache row")
        XCTAssertEqual(cached.first?.profileURL, "/bob.jpg")
    }

    @MainActor
    func testPrefersCachedOverCastMember() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PersonImageEntity(name: "Carol", profileURL: "/fresh.jpg"))
        context.insert(CastMember(name: "Carol", characterName: "", profileURL: "/stale.jpg"))
        try context.save()

        let resolved = PersonImageResolver.resolve(for: "Carol", in: context)
        XCTAssertEqual(resolved, "/fresh.jpg", "PersonImageEntity cache should take priority")
    }

    @MainActor
    func testReturnsNilWhenNoSourcesExist() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let resolved = PersonImageResolver.resolve(for: "Nobody", in: context)

        XCTAssertNil(resolved)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PersonImageEntity>()).isEmpty, "No cache row should be created for an unknown person")
    }

    @MainActor
    func testCurrentURLOverridesEverything() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let resolved = PersonImageResolver.resolve(for: "Dave", in: context, currentURL: "/already.jpg")

        XCTAssertEqual(resolved, "/already.jpg")
        XCTAssertTrue(try context.fetch(FetchDescriptor<PersonImageEntity>()).isEmpty)
    }
}
