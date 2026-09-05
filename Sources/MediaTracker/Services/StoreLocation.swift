import Foundation
import SwiftData
import SQLite3
import os

/// Owns the app's SwiftData store location.
///
/// The production store MUST live in the app's own directory
/// (`~/Library/Application Support/MediaTracker/default.store`), never the
/// shared SwiftData default path (`~/Library/Application Support/default.store`).
/// System daemons (observed: `/usr/libexec/icloudmailagent` on macOS 26 beta,
/// Sep 2026) create their own SwiftData stores at that shared default path and
/// clobber whatever is there — which silently replaced the entire library once.
/// The one-time migration moves an owned legacy store into the app's directory;
/// a foreign store at the legacy path is detected and left untouched.
enum StoreLocation {
    static let devBundleIdentifier = "com.vara.mediatracker.dev"
    static let devDirectoryName = "MediaTracker Dev"
    static let productionDirectoryName = "MediaTracker"
    static let storeFilename = "default.store"

    static var isDevBundle: Bool {
        Bundle.main.bundleIdentifier == devBundleIdentifier
    }

    static func makeConfiguration(schema: Schema) throws -> ModelConfiguration {
        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        if isDevBundle {
            let storeDirectory = applicationSupportDirectory.appendingPathComponent(
                devDirectoryName,
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
            return ModelConfiguration(
                schema: schema,
                url: storeDirectory.appendingPathComponent(storeFilename)
            )
        }

        let storeDirectory = applicationSupportDirectory.appendingPathComponent(
            productionDirectoryName,
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let storeURL = storeDirectory.appendingPathComponent(storeFilename)
        migrateLegacyStoreIfNeeded(newStoreURL: storeURL, applicationSupportDirectory: applicationSupportDirectory)
        return ModelConfiguration(schema: schema, url: storeURL)
    }

    /// One-time migration of the legacy shared-path store into the app's own
    /// directory. Only runs when the new store doesn't exist yet, and only when
    /// the legacy file actually contains MediaTracker tables — a foreign store
    /// at the legacy path (e.g. a system daemon's) is left completely alone.
    static func migrateLegacyStoreIfNeeded(newStoreURL: URL, applicationSupportDirectory: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: newStoreURL.path) else { return }

        let legacyURL = applicationSupportDirectory.appendingPathComponent(storeFilename)
        guard fm.fileExists(atPath: legacyURL.path) else { return }
        guard legacyStoreContainsMediaTrackerSchema(legacyURL) else {
            AppLogger.data.warning("🚚 Legacy default.store holds foreign tables — not migrating (another app owns it)")
            return
        }

        do {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: legacyURL.path + suffix)
                guard fm.fileExists(atPath: source.path) else { continue }
                let destination = URL(fileURLWithPath: newStoreURL.path + suffix)
                try fm.moveItem(at: source, to: destination)
            }
            AppLogger.data.warning("🚚 Migrated legacy store to app-owned directory: \(newStoreURL.path, privacy: .public)")
        } catch {
            // If the move partially failed, abort cleanly: creating the
            // container at the new URL would then start from a fresh store.
            AppLogger.data.error("🚚 Legacy store migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Checks the legacy SQLite file actually contains MediaTracker's schema
    /// (`ZMEDIAITEM`) before claiming it. Opened read-write because read-only
    /// opens of WAL-mode databases need to create a -shm beside the file.
    static func legacyStoreContainsMediaTrackerSchema(_ url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, db != nil else {
            if let db { sqlite3_close(db) }
            return false
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ZMEDIAITEM' LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, statement != nil else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }
}
