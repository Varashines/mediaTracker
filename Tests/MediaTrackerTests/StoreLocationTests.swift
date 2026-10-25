import XCTest
import SwiftData
import SQLite3
@testable import MediaTracker

/// Guards the store-location ownership check that protects against the
/// icloudmailagent-style clobbering of the shared default SwiftData path.
@MainActor
final class StoreLocationTests: MTTestCase {
    private var workDirectory: URL!

    override func setUp() {
        super.setUp()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoreLocationTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
        super.tearDown()
    }

    private func makeOwnedStore(at url: URL) throws {
        let container = try ModelContainer(
            for: Schema([MediaItem.self]),
            configurations: ModelConfiguration(url: url)
        )
        container.mainContext.insert(MediaItem(id: "movie_1", title: "T", overview: "", type: .movie))
        try container.mainContext.save()
        container.mainContext.autosaveEnabled = false
    }

    private func makeForeignStore(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, db != nil else {
            return XCTFail("Could not create test sqlite file")
        }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE ZMAILTHING (Z_PK INTEGER PRIMARY KEY);", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO ZMAILTHING (Z_PK) VALUES (1);", nil, nil, nil)
    }

    func testRecognizesOwnedMediaTrackerSchema() throws {
        let url = workDirectory.appendingPathComponent("owned.store")
        try makeOwnedStore(at: url)
        XCTAssertTrue(StoreLocation.legacyStoreContainsMediaTrackerSchema(url))
    }

    func testRejectsForeignSchema() throws {
        let url = workDirectory.appendingPathComponent("foreign.store")
        try makeForeignStore(at: url)
        XCTAssertFalse(StoreLocation.legacyStoreContainsMediaTrackerSchema(url))
    }

    func testRejectsMissingFile() {
        let url = workDirectory.appendingPathComponent("missing.store")
        XCTAssertFalse(StoreLocation.legacyStoreContainsMediaTrackerSchema(url))
    }

    /// Migration: an owned legacy store is moved (with WAL sidecars) into the
    /// new location; a foreign store is left exactly where it is.
    func testMigrationMovesOwnedLegacyStoreWithSidecars() throws {
        let legacyURL = workDirectory.appendingPathComponent("default.store")
        try makeOwnedStore(at: legacyURL)
        try "wal".write(to: workDirectory.appendingPathComponent("default.store-wal"), atomically: true, encoding: .utf8)
        try "shm".write(to: workDirectory.appendingPathComponent("default.store-shm"), atomically: true, encoding: .utf8)
        let newURL = workDirectory.appendingPathComponent("MediaTracker").appendingPathComponent("default.store")
        try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        StoreLocation.migrateLegacyStoreIfNeeded(newStoreURL: newURL, applicationSupportDirectory: workDirectory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(StoreLocation.legacyStoreContainsMediaTrackerSchema(newURL))
    }

    func testMigrationSkipsForeignLegacyStore() throws {
        let legacyURL = workDirectory.appendingPathComponent("default.store")
        try makeForeignStore(at: legacyURL)
        let newURL = workDirectory.appendingPathComponent("MediaTracker").appendingPathComponent("default.store")
        try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        StoreLocation.migrateLegacyStoreIfNeeded(newStoreURL: newURL, applicationSupportDirectory: workDirectory)

        // Foreign file untouched, no store created at the new location yet.
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: newURL.path))
    }

    func testMigrationSkipsWhenNewStoreAlreadyExists() throws {
        let legacyURL = workDirectory.appendingPathComponent("default.store")
        try makeOwnedStore(at: legacyURL)
        let newURL = workDirectory.appendingPathComponent("MediaTracker").appendingPathComponent("default.store")
        try FileManager.default.createDirectory(at: newURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try makeOwnedStore(at: newURL)

        StoreLocation.migrateLegacyStoreIfNeeded(newStoreURL: newURL, applicationSupportDirectory: workDirectory)

        // Existing new store untouched; legacy file still in place.
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertTrue(StoreLocation.legacyStoreContainsMediaTrackerSchema(newURL))
    }

    // MARK: - Corruption-recovery backup compatibility (P0-1)

    /// Regression: the compatibility check split the underscore form on ".",
    /// so a sidecar holding "10_1_0" produced "10_1_0" and never matched "10".
    /// No backup was ever considered compatible, so none was ever restored.
    func testCompatibleBackupAcceptsUnderscoreVersionFromOlderBuilds() {
        XCTAssertTrue(StoreLocation.isCompatibleBackupVersion("10_1_0", currentVersion: "10.1.0"))
    }

    func testCompatibleBackupAcceptsDottedVersion() {
        XCTAssertTrue(StoreLocation.isCompatibleBackupVersion("10.1.0", currentVersion: "10.2.3"))
    }

    func testCompatibleBackupAcceptsTrailingNewline() {
        XCTAssertTrue(StoreLocation.isCompatibleBackupVersion("10.1.0\n", currentVersion: "10.1.0"))
    }

    func testCompatibleBackupRejectsDifferentMajorVersion() {
        XCTAssertFalse(StoreLocation.isCompatibleBackupVersion("9.6.4", currentVersion: "10.1.0"))
        XCTAssertFalse(StoreLocation.isCompatibleBackupVersion("10.1.0", currentVersion: "11.0.0"))
    }

    func testCompatibleBackupRejectsUnknownAndEmptyVersions() {
        XCTAssertFalse(StoreLocation.isCompatibleBackupVersion("unknown", currentVersion: "10.1.0"))
        XCTAssertFalse(StoreLocation.isCompatibleBackupVersion("", currentVersion: "10.1.0"))
        XCTAssertFalse(StoreLocation.isCompatibleBackupVersion("10.1.0", currentVersion: ""))
    }

    /// The restore must replace the store and keep a copy of what it overwrote,
    /// so a restore that turns out to be wrong is not itself a data loss.
    func testRestoreBackupReplacesStoreAndPreservesPreviousCopy() throws {
        let backupURL = workDirectory.appendingPathComponent("default_corrupted_v10_1_0_1.store")
        try makeOwnedStore(at: backupURL)
        let storeURL = workDirectory.appendingPathComponent("default.store")
        try makeForeignStore(at: storeURL)

        XCTAssertTrue(StoreLocation.restoreBackup(at: backupURL, over: storeURL))

        XCTAssertTrue(StoreLocation.legacyStoreContainsMediaTrackerSchema(storeURL))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: workDirectory.appendingPathComponent("default_current_saved.store").path
            )
        )
    }

    /// CoreData names the WAL "default.store-wal". Copying "default.store.wal"
    /// silently copied nothing, which left restored stores without their sidecars.
    func testRestoreBackupCopiesWalUsingCoreDataNaming() throws {
        let backupURL = workDirectory.appendingPathComponent("default_corrupted_v10_1_0_2.store")
        try makeOwnedStore(at: backupURL)
        try "wal".write(to: URL(fileURLWithPath: backupURL.path + "-wal"), atomically: true, encoding: .utf8)
        let storeURL = workDirectory.appendingPathComponent("default.store")

        XCTAssertTrue(StoreLocation.restoreBackup(at: backupURL, over: storeURL))

        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path + ".wal"))
    }

    func testRestoreBackupFailsWhenBackupIsMissing() {
        let storeURL = workDirectory.appendingPathComponent("default.store")
        let missing = workDirectory.appendingPathComponent("not-a-backup.store")

        XCTAssertFalse(StoreLocation.restoreBackup(at: missing, over: storeURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path))
    }
}
