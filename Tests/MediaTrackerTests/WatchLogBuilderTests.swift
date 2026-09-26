import XCTest
import SwiftData
@testable import MediaTracker

/// The watch log is a pure aggregation over cycles + events, so the grouping,
/// rewatch numbering and date maths are verified without a view.
@MainActor
final class WatchLogBuilderTests: MTTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([MediaItem.self, TVShowDetails.self, TVSeason.self, TVEpisode.self, WatchCycle.self, WatchEvent.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeCycle(
        _ context: ModelContext,
        mediaID: String,
        startedAt: Date,
        completedAt: Date? = nil,
        state: WatchCycleState = .completed,
        isRewatch: Bool = false,
        isBackfilled: Bool = false,
        isComplete: Bool = true
    ) -> WatchCycle {
        let cycle = WatchCycle(
            mediaID: mediaID,
            kind: .tvShow,
            startedAt: startedAt,
            completedAt: completedAt,
            state: state,
            isBackfilled: isBackfilled,
            isRewatch: isRewatch,
            isComplete: isComplete
        )
        context.insert(cycle)
        return cycle
    }

    private func makeEvent(
        _ context: ModelContext,
        cycle: WatchCycle,
        mediaID: String,
        episodeID: String?,
        watchedAt: Date,
        runtime: Int = 42,
        voidedAt: Date? = nil
    ) -> WatchEvent {
        let event = WatchEvent(
            cycleID: cycle.id,
            mediaID: mediaID,
            episodeID: episodeID,
            watchedAt: watchedAt,
            source: .manual,
            runtimeMinutes: runtime,
            voidedAt: voidedAt,
            deduplicationKey: "\(cycle.id.uuidString):\(episodeID ?? "movie")\(voidedAt == nil ? "" : ":\(UUID().uuidString)")"
        )
        context.insert(event)
        return event
    }

    private let mediaID = "tv_900"
    private lazy var firstWatch = Date(timeIntervalSince1970: 1_000_000)
    private lazy var firstRewatch = Date(timeIntervalSince1970: 2_000_000)
    private lazy var secondRewatch = Date(timeIntervalSince1970: 3_000_000)

    func testPassesAreNewestFirstWithStableRewatchNumbering() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = makeCycle(context, mediaID: mediaID, startedAt: firstWatch)
        let rewatchOne = makeCycle(context, mediaID: mediaID, startedAt: firstRewatch, isRewatch: true)
        let rewatchTwo = makeCycle(context, mediaID: mediaID, startedAt: secondRewatch, isRewatch: true)
        try context.save()

        let passes = WatchLogBuilder.passes(
            cycles: try context.fetch(FetchDescriptor<WatchCycle>()),
            events: try context.fetch(FetchDescriptor<WatchEvent>())
        )

        XCTAssertEqual(passes.map(\.title), ["Rewatch 2", "Rewatch", "First watch"])
        XCTAssertEqual(passes.map(\.id), [rewatchTwo.id, rewatchOne.id, first.id])
    }

    func testRewatchNumberingIsIndependentOfInputOrder() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let a = makeCycle(context, mediaID: mediaID, startedAt: firstWatch)
        let b = makeCycle(context, mediaID: mediaID, startedAt: firstRewatch, isRewatch: true)
        try context.save()

        let forward = WatchLogBuilder.passes(cycles: [a, b], events: [])
        let reversed = WatchLogBuilder.passes(cycles: [b, a], events: [])
        XCTAssertEqual(forward.map(\.title), reversed.map(\.title))
    }

    func testPassAggregatesOccurrenceCountRuntimeAndDateRange() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cycle = makeCycle(
            context,
            mediaID: mediaID,
            startedAt: firstWatch,
            completedAt: firstWatch.addingTimeInterval(86400 * 2)
        )
        makeEvent(context, cycle: cycle, mediaID: mediaID, episodeID: "900_1_1", watchedAt: firstWatch, runtime: 45)
        makeEvent(context, cycle: cycle, mediaID: mediaID, episodeID: "900_1_2", watchedAt: firstWatch.addingTimeInterval(3600), runtime: 45)
        makeEvent(context, cycle: cycle, mediaID: mediaID, episodeID: "900_1_3", watchedAt: firstWatch.addingTimeInterval(86400 * 2), runtime: 30)
        try context.save()

        let pass = try XCTUnwrap(WatchLogBuilder.passes(
            cycles: try context.fetch(FetchDescriptor<WatchCycle>()),
            events: try context.fetch(FetchDescriptor<WatchEvent>())
        ).first)

        XCTAssertEqual(pass.occurrenceCount, 3)
        XCTAssertEqual(pass.runtimeMinutes, 120)
        XCTAssertEqual(pass.earliestOccurrence, firstWatch)
        XCTAssertEqual(pass.latestOccurrence, firstWatch.addingTimeInterval(86400 * 2))
        let range = try XCTUnwrap(pass.dateRangeDescription)
        XCTAssertTrue(range.contains("–"), "a multi-day pass shows a range: \(range)")
    }

    /// A second watch of the same episode in a later pass is a real occurrence;
    /// within one pass it must not be double counted.
    func testDuplicateOccurrencesInOnePassCountOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cycle = makeCycle(context, mediaID: mediaID, startedAt: firstWatch)
        makeEvent(context, cycle: cycle, mediaID: mediaID, episodeID: "900_1_1", watchedAt: firstWatch)
        makeEvent(context, cycle: cycle, mediaID: mediaID, episodeID: "900_1_1", watchedAt: firstWatch.addingTimeInterval(60))
        try context.save()

        let pass = try XCTUnwrap(WatchLogBuilder.passes(
            cycles: try context.fetch(FetchDescriptor<WatchCycle>()),
            events: try context.fetch(FetchDescriptor<WatchEvent>())
        ).first)
        XCTAssertEqual(pass.occurrenceCount, 1)
    }

    func testVoidedEventsAreExcluded() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cycle = makeCycle(context, mediaID: mediaID, startedAt: firstWatch)
        makeEvent(context, cycle: cycle, mediaID: mediaID, episodeID: "900_1_1", watchedAt: firstWatch)
        makeEvent(context, cycle: cycle, mediaID: mediaID, episodeID: "900_1_2", watchedAt: firstWatch, voidedAt: firstWatch)
        try context.save()

        let pass = try XCTUnwrap(WatchLogBuilder.passes(
            cycles: try context.fetch(FetchDescriptor<WatchCycle>()),
            events: try context.fetch(FetchDescriptor<WatchEvent>())
        ).first)
        XCTAssertEqual(pass.occurrenceCount, 1, "an unwatched episode must not appear in the log")
    }

    /// Archiving a finished cycle must not read as "partial" — `isComplete`
    /// survives the state change.
    func testArchivedCompletedCycleReadsAsCompleted() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cycle = makeCycle(
            context,
            mediaID: mediaID,
            startedAt: firstWatch,
            state: .archived,
            isRewatch: true,
            isComplete: true
        )
        makeEvent(context, cycle: cycle, mediaID: mediaID, episodeID: "900_1_1", watchedAt: firstWatch)
        try context.save()

        let pass = try XCTUnwrap(WatchLogBuilder.passes(
            cycles: try context.fetch(FetchDescriptor<WatchCycle>()),
            events: try context.fetch(FetchDescriptor<WatchEvent>())
        ).first)
        XCTAssertTrue(pass.isFinished)
        XCTAssertEqual(pass.stateDescription, "Completed")
    }

    func testPartialRewatchReadsAsPartial() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cycle = makeCycle(
            context,
            mediaID: mediaID,
            startedAt: firstRewatch,
            state: .archived,
            isRewatch: true,
            isComplete: false
        )
        makeEvent(context, cycle: cycle, mediaID: mediaID, episodeID: "900_1_1", watchedAt: firstRewatch)
        try context.save()

        let pass = try XCTUnwrap(WatchLogBuilder.passes(
            cycles: try context.fetch(FetchDescriptor<WatchCycle>()),
            events: try context.fetch(FetchDescriptor<WatchEvent>())
        ).first)
        XCTAssertFalse(pass.isFinished)
        XCTAssertEqual(pass.stateDescription, "Partial")
    }

    func testMoviePassCountsAtLeastOneOccurrence() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let cycle = WatchCycle(
            mediaID: "movie_1",
            kind: .movie,
            startedAt: firstWatch,
            completedAt: firstWatch,
            state: .completed,
            isComplete: true
        )
        context.insert(cycle)
        try context.save()

        let pass = try XCTUnwrap(WatchLogBuilder.passes(
            cycles: try context.fetch(FetchDescriptor<WatchCycle>()),
            events: []
        ).first)
        XCTAssertEqual(pass.occurrenceCount, 1, "a completed movie always counts as one watch")
    }

    func testSummaryReportsPassesRuntimeAndStart() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let a = makeCycle(context, mediaID: mediaID, startedAt: firstWatch)
        let b = makeCycle(context, mediaID: mediaID, startedAt: firstRewatch, isRewatch: true)
        makeEvent(context, cycle: a, mediaID: mediaID, episodeID: "900_1_1", watchedAt: firstWatch, runtime: 60)
        makeEvent(context, cycle: b, mediaID: mediaID, episodeID: "900_1_1", watchedAt: firstRewatch, runtime: 30)
        try context.save()

        let passes = WatchLogBuilder.passes(
            cycles: try context.fetch(FetchDescriptor<WatchCycle>()),
            events: try context.fetch(FetchDescriptor<WatchEvent>())
        )
        let summary = WatchLogBuilder.summary(passes: passes, firstWatchedAt: firstWatch)
        XCTAssertTrue(summary.contains("2 completed passes"), summary)
        XCTAssertTrue(summary.contains("since"), summary)
    }

    func testSummaryWithNoPassesFallsBackToFirstWatchedDate() {
        let summary = WatchLogBuilder.summary(passes: [], firstWatchedAt: firstWatch)
        XCTAssertTrue(summary.contains("First watched"), summary)

        let none = WatchLogBuilder.summary(passes: [], firstWatchedAt: nil)
        XCTAssertTrue(none.contains("No watch history"), none)
    }
}
