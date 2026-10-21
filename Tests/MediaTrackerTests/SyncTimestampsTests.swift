import XCTest
@testable import MediaTracker

/// Pins the conflict rules the sync rests on, and the case that made them necessary.
///
/// Android formatted timestamps from local wall-clock time and appended a literal `Z`, so every
/// row it edited arrived up to hours in the future. A future stamp is permanently newer, so a
/// later edit made here could never win the conflict and the phone's value was re-pushed on every
/// sync — with the pull watermark (derived from the same stamps) dragged along with it.
final class SyncTimestampsTests: XCTestCase {

    // MARK: - Clamp

    func testClampLeavesPastEditTimesAlone() {
        let now = Date()
        let past = now.addingTimeInterval(-3600)
        XCTAssertEqual(SyncTimestamps.clampToNow(past, now: now), past)
    }

    func testClampBoundsFutureEditTimes() {
        let now = Date()
        let future = now.addingTimeInterval(4 * 3600)
        XCTAssertEqual(SyncTimestamps.clampToNow(future, now: now), now)
    }

    func testClampTreatsNoDateAsNoDate() {
        XCTAssertEqual(SyncTimestamps.clampToNow(.distantPast), .distantPast)
    }

    // MARK: - Remote edit time

    func testRemoteEditTimePrefersTheEditStamp() {
        let now = Date()
        let edit = now.addingTimeInterval(-600)
        let write = now.addingTimeInterval(-30)
        XCTAssertEqual(
            SyncTimestamps.remoteEditTime(lastInteraction: edit, updatedAt: write, now: now),
            edit
        )
    }

    func testRemoteEditTimeFallsBackToWriteStampForRowsWithoutAnEditStamp() {
        let now = Date()
        let write = now.addingTimeInterval(-30)
        XCTAssertEqual(
            SyncTimestamps.remoteEditTime(lastInteraction: nil, updatedAt: write, now: now),
            write
        )
    }

    func testRemoteEditTimeIsDistantPastWhenNeitherStampExists() {
        XCTAssertEqual(SyncTimestamps.remoteEditTime(lastInteraction: nil, updatedAt: nil), .distantPast)
    }

    func testRemoteEditTimeBoundsAFutureRemoteStamp() {
        let now = Date()
        let futureEdit = now.addingTimeInterval(4 * 3600)
        XCTAssertEqual(
            SyncTimestamps.remoteEditTime(lastInteraction: futureEdit, updatedAt: now, now: now),
            now
        )
    }

    // MARK: - The regression

    /// The Hokum case, at the level of the comparison that decided it.
    func testFutureStampedEditNoLongerOutranksALaterRemoteEdit() {
        let now = Date()
        let phoneStamp = now.addingTimeInterval(4 * 3600)   // bad clock, four hours ahead
        let macEdit = now.addingTimeInterval(60)            // a genuine edit made a minute later

        // Before: the remote could never win, so the Mac's edit was dropped and the phone's
        // value was re-pushed forever.
        XCTAssertFalse(macEdit > phoneStamp)

        // After: the stamp is bounded, so the next real edit wins normally.
        XCTAssertTrue(macEdit > SyncTimestamps.clampToNow(phoneStamp, now: now))
    }

    /// A row re-written later must not outrank a genuine edit: the write stamp is not an edit.
    func testWriteTimeDoesNotOutrankAnEdit() {
        let now = Date()
        let localEdit = now.addingTimeInterval(-60)
        let remoteEdit = SyncTimestamps.remoteEditTime(
            lastInteraction: now.addingTimeInterval(-3600),   // edited an hour ago…
            updatedAt: now.addingTimeInterval(-30),           // …but re-written 30s ago
            now: now
        )
        XCTAssertLessThan(remoteEdit, localEdit)
    }

    // MARK: - Wiring

    func testItemSyncEditTimeIsBounded() {
        let item = MediaItem(id: "movie_1", title: "T", overview: "", type: .movie)
        item.lastInteractionDate = Date().addingTimeInterval(4 * 3600)
        XCTAssertLessThanOrEqual(item.syncEditTime, Date().addingTimeInterval(1))
    }

    func testItemSyncEditTimeFallsBackToTheStateChangeDate() {
        let item = MediaItem(id: "movie_2", title: "T", overview: "", type: .movie)
        let stateChange = Date().addingTimeInterval(-120)
        item.lastInteractionDate = nil
        item.lastStateChangeDate = stateChange
        XCTAssertEqual(item.syncEditTime, stateChange)
    }
}
