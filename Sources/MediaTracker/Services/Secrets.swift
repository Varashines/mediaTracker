import Foundation
import Security

/// A credential rather than a preference.
///
/// These five values are the only ones in the app that are worth stealing: three API keys and the
/// two halves of the Supabase connection. Everything else in `UserDefaultsKeys` is a preference —
/// "which palette", "is the digest on" — and belongs in the defaults plist.
///
/// The raw values are the keys they were stored under before this store existed, which is what
/// makes the one-time migration in `Secrets.migrateFromDefaultsIfNeeded()` a straight copy.
enum SecretKey: String, CaseIterable, Sendable {
    case tmdb = "tmdb_api_key"
    case omdb = "omdb_api_key"
    case mooreMetrics = "mm_api_key"
    /// The shared secret the two devices authenticate their sync with. The one that matters.
    case cloudSyncKey = "cloud_sync_key"
    case cloudSyncAnonKey = "cloud_sync_anon_key"
}

/// Credentials, in the login Keychain rather than in `UserDefaults`.
///
/// ## Why the Keychain, and why it does not ask for anything
///
/// A keychain item is unreadable to other processes, unlike a preferences plist, which any process
/// running as the user can just read. That is the whole security argument, and it costs nothing at
/// runtime *if* the item has no access-control policy: no `SecAccessControl`, no `.userPresence`,
/// so macOS never asks for Touch ID or a password. The item is readable by the app that owns it,
/// exactly like the plist was.
///
/// The one thing that can reintroduce prompts is code signing. A keychain item remembers the
/// *designated requirement* of the app that created it. Ad-hoc signing (`codesign --sign -`) derives
/// that requirement from the binary's cdhash, so every rebuild looks like a different app and macOS
/// asks again. Signing with any certificate — including a self-signed one, which needs no developer
/// account — makes the requirement `identifier + certificate`, which survives rebuilds. So the app
/// is silent on a machine where `install.sh` signs with a stable identity, and noisy on one where
/// it does not. `install.sh` says which of the two it did.
///
/// ## Why there is a cache
///
/// `SecItemCopyMatching` is a synchronous IPC to `securityd`. A request builder may ask for a key
/// several times per API call, and the cache turns those into a dictionary lookup. Writes go through
/// to the Keychain immediately, so the cache can never be newer than the store.
///
/// ## Why tests do not use the Keychain
///
/// `swift test` runs inside `xctest`, which is not this app: the same item would prompt, and a
/// headless test run would hang on a dialog nobody can click. Outside the app bundle this type
/// transparently reads and writes `UserDefaults`, which is exactly where tests already put their
/// fixtures, so no test had to change.
enum Secrets {
    // MARK: - Public API

    /// The current value, or the empty string when unset. Never nil: every call site treats an
    /// empty key as "not configured", and an empty string says that without an unwrap.
    static func value(for key: SecretKey) -> String {
        guard isApp else {
            // Outside the app there is no Keychain item to read, and no cache either: tests seed
            // UserDefaults between cases, and a process-wide cache would hand the next test the
            // previous one's answer.
            return UserDefaults.standard.string(forKey: key.rawValue) ?? ""
        }
        if let cached = cached(key) { return cached }
        let stored = readFromKeychain(key) ?? ""
        store(stored, for: key)
        return stored
    }

    static func has(_ key: SecretKey) -> Bool {
        !value(for: key).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func set(_ value: String, for key: SecretKey) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isApp else {
            UserDefaults.standard.set(trimmed, forKey: key.rawValue)
            return
        }
        store(trimmed, for: key)
        writeToKeychain(trimmed, for: key)
    }

    static func clear(_ key: SecretKey) {
        if isApp {
            store("", for: key)
            deleteFromKeychain(key)
        }
        // Always clear the defaults copy too: a stale one would be migrated back on next launch.
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }

    static func clearAll() {
        SecretKey.allCases.forEach(clear)
    }

    /// Moves credentials written by a build that stored them in `UserDefaults` into the Keychain,
    /// then deletes the plaintext copies. Safe to call on every launch: it only acts on a non-empty
    /// defaults value, and only after the Keychain has nothing for that key.
    ///
    /// The defaults copy is removed only once the Keychain read-back confirms the value is there.
    /// A migration that trusts its own write is a migration that can delete the only copy of a
    /// credential when the write failed — the one failure mode this whole change must not have.
    static func migrateFromDefaultsIfNeeded() {
        guard isApp else { return }
        let defaults = UserDefaults.standard
        var moved = 0
        for key in SecretKey.allCases {
            guard let legacy = defaults.string(forKey: key.rawValue) else { continue }
            let trimmed = legacy.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                defaults.removeObject(forKey: key.rawValue)
                continue
            }
            if (readFromKeychain(key) ?? "").isEmpty {
                writeToKeychain(trimmed, for: key)
                guard readFromKeychain(key) == trimmed else {
                    AppLogger.error("Keychain migration for \(key.rawValue) did not read back; leaving the defaults copy in place")
                    continue
                }
                store(trimmed, for: key)
                moved += 1
            }
            defaults.removeObject(forKey: key.rawValue)
        }
        if moved > 0 {
            AppLogger.info("Moved \(moved) credential(s) from UserDefaults to the Keychain")
        }
    }

    // MARK: - Environment

    /// True only inside one of the app bundles. The dev bundle gets its own service, so the two
    /// never read each other's items (which would prompt, because they are different requirements).
    private static var bundleID: String? { Bundle.main.bundleIdentifier }

    private static var isApp: Bool {
        bundleID == "com.vara.mediatracker" || bundleID == "com.vara.mediatracker.dev"
    }

    private static var service: String {
        "\(bundleID ?? "com.vara.mediatracker").credentials"
    }

    // MARK: - Cache

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: String] = [:]

    private static func cached(_ key: SecretKey) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key.rawValue]
    }

    private static func store(_ value: String, for key: SecretKey) {
        lock.lock()
        cache[key.rawValue] = value
        lock.unlock()
    }

    /// Test seam, matching `ImageCache.configureForTesting`. Empties the cache so the next read goes
    /// back to the store — used when a test changes the defaults a fixture was seeded with.
    static func invalidateCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // MARK: - Keychain

    private static func baseQuery(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }

    private static func readFromKeychain(_ key: SecretKey) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                AppLogger.error("Keychain read for \(key.rawValue) failed: \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Update-then-add rather than delete-then-add: a delete would briefly leave the credential
    /// absent, and two writers racing (the settings screen and the sync engine generating a key)
    /// could lose one of the values.
    private static func writeToKeychain(_ value: String, for key: SecretKey) {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var add = baseQuery(key)
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess {
                AppLogger.error("Keychain add for \(key.rawValue) failed: \(addStatus)")
            }
        } else if status != errSecSuccess {
            AppLogger.error("Keychain update for \(key.rawValue) failed: \(status)")
        }
    }

    private static func deleteFromKeychain(_ key: SecretKey) {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.error("Keychain delete for \(key.rawValue) failed: \(status)")
        }
    }
}
