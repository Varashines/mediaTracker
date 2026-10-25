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

    // MARK: - Corruption-recovery backups

    /// Suffix appended to the store path for SQLite's write-ahead log and shared
    /// memory file. CoreData/SwiftData name these `default.store-wal` and
    /// `default.store-shm` — *not* `default.store.wal`, which is what
    /// `appendingPathExtension("wal")` produces. Every sidecar copy that used the
    /// extension form silently pointed at a file that never existed.
    static let storeSidecarSuffixes = ["-wal", "-shm"]

    /// The `-wal`/`-shm` files that belong to `storeURL`.
    static func sidecarURLs(for storeURL: URL) -> [URL] {
        storeSidecarSuffixes.map { URL(fileURLWithPath: storeURL.path + $0) }
    }

    /// Whether a backup recorded by `recordedVersion` may be offered to a release
    /// running `currentVersion`.
    ///
    /// Compares major versions only, and accepts both the dotted form read from
    /// `CFBundleShortVersionString` ("10.1.0") and the underscore form ("10_1_0")
    /// that older builds derived from the backup's file name. That legacy form is
    /// what broke the restore: `"10_1_0".split(separator: ".")` yields `["10_1_0"]`,
    /// which can never equal `"10"`, so no backup was ever considered compatible.
    static func isCompatibleBackupVersion(_ recordedVersion: String, currentVersion: String) -> Bool {
        guard let recorded = majorVersionComponent(of: recordedVersion),
              let current = majorVersionComponent(of: currentVersion),
              recorded != "unknown", current != "unknown"
        else { return false }
        return recorded == current
    }

    static func majorVersionComponent(of version: String) -> String? {
        let normalized = version
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: ".")
        guard let major = normalized.split(separator: ".").first, !major.isEmpty else { return nil }
        return String(major)
    }

    /// Restores `backupURL` over `storeURL`, preserving whatever is currently there.
    ///
    /// Returns `true` only when the store file was actually replaced, so the caller can
    /// decide whether the one-shot restore flag has been earned. A store that cannot be
    /// preserved first is left alone rather than overwritten: a failed restore must not
    /// become a second data loss.
    @discardableResult
    static func restoreBackup(at backupURL: URL, over storeURL: URL) -> Bool {
        let fm = FileManager.default
        let preservedURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("default_current_saved.store")

        try? fm.removeItem(at: preservedURL)
        if fm.fileExists(atPath: storeURL.path) {
            do {
                try fm.copyItem(at: storeURL, to: preservedURL)
            } catch {
                AppLogger.data.error("♻️ Refusing to restore: could not preserve the current store (\(error.localizedDescription, privacy: .public))")
                return false
            }
        }

        // Remove the live store *and* its sidecars. A stale -wal left beside a
        // restored store would replay transactions that belong to the old one.
        try? fm.removeItem(at: storeURL)
        for sidecar in sidecarURLs(for: storeURL) { try? fm.removeItem(at: sidecar) }

        do {
            try fm.copyItem(at: backupURL, to: storeURL)
        } catch {
            AppLogger.data.error("♻️ Backup restore failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        // Sidecars are optional: a backup may have been taken without them.
        for (source, destination) in zip(sidecarURLs(for: backupURL), sidecarURLs(for: storeURL))
        where fm.fileExists(atPath: source.path) {
            try? fm.copyItem(at: source, to: destination)
        }

        return fm.fileExists(atPath: storeURL.path)
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
        // The file may still be held by the store that just wrote it — this runs at
        // launch, and in tests immediately after a container is created. Without a busy
        // timeout a transient lock reads as "not our schema", and the legacy store is
        // abandoned instead of migrated.
        sqlite3_busy_timeout(db, 2000)

        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'ZMEDIAITEM' LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, statement != nil else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }
}
