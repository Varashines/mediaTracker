import Foundation
import Security

/// A credential rather than a preference.
///
/// These five values are the only ones in the app that are worth stealing: three API keys and the
/// two halves of the Supabase connection. Everything else in `UserDefaultsKeys` is a preference —
/// "which palette", "is the digest on" — and belongs in the defaults plist.
///
/// The raw values are the keys they were stored under before this store existed, which is what
/// makes the one-time migrations in `Secrets.migrateFromDefaultsIfNeeded()` and the legacy
/// Keychain import a straight copy.
enum SecretKey: String, CaseIterable, Sendable {
    case tmdb = "tmdb_api_key"
    case omdb = "omdb_api_key"
    case mooreMetrics = "mm_api_key"
    /// The shared secret the two devices authenticate their sync with. The one that matters.
    case cloudSyncKey = "cloud_sync_key"
    case cloudSyncAnonKey = "cloud_sync_anon_key"
}

/// Credentials in an encrypted file, unlocked by one Keychain-held master key.
///
/// ## Why a vault instead of one Keychain item per secret
///
/// Five items mean five ACLs: a signing-identity change asks for approval once per item, and a
/// machine backup carries five blobs whose ACLs are meaningless elsewhere. Here the ACL covers a
/// single 32-byte key, the secrets themselves are AES-GCM ciphertext in
/// `Application Support/<app>/credentials.vault`, and the payload backs up as one file.
///
/// The Keychain is still what stands between another process and the vault: without the master key
/// the file is random bytes. The vault changes how many items participate, not whether the OS guards
/// them. It also means the secrets are never plaintext at rest, which the per-item layout did not
/// offer.
///
/// ## Why it does not ask for anything
///
/// The master key item has no access-control policy: no `SecAccessControl`, no `.userPresence`, so
/// macOS never asks for Touch ID or a password. It is readable by the app that owns it.
///
/// The one thing that can reintroduce prompts is code signing. A Keychain item remembers the
/// *designated requirement* of the app that created it. Ad-hoc signing (`codesign --sign -`) derives
/// that requirement from the binary's cdhash, so every rebuild looks like a different app and macOS
/// asks again. Signing with any certificate — including a self-signed one — makes the requirement
/// `identifier + certificate`, which survives rebuilds. One item means at most one approval in that
/// situation instead of five. `install.sh` says which identity was used.
///
/// ## Migration
///
/// Two one-time copies run behind the same read-back discipline:
///
/// 1. `migrateFromDefaultsIfNeeded()` moves plaintext `UserDefaults` values into the vault.
/// 2. The first vault read also imports the per-key Keychain items written by older builds, and only
///    deletes them after the new file has been read back and compared.
///
/// A migration that trusts its own write is a migration that can delete the only copy of a credential
/// when the write failed, so neither path removes the source until the destination verifies.
///
/// ## Why tests do not use the vault
///
/// `swift test` runs inside `xctest`, which is not this app: reading the master key would prompt, and
/// a headless run would hang on a dialog nobody can click. Outside the app bundle this type
/// transparently reads and writes `UserDefaults`, which is exactly where tests already put their
/// fixtures, so no test had to change. `CredentialVault` itself is tested directly with an injected
/// key provider.
enum Secrets {
    // MARK: - Public API

    /// The current value, or the empty string when unset. Never nil: every call site treats an
    /// empty key as "not configured", and an empty string says that without an unwrap.
    static func value(for key: SecretKey) -> String {
        guard isApp else {
            // Outside the app there is no vault to read, and no cache either: tests seed
            // UserDefaults between cases, and a process-wide cache would hand the next test the
            // previous one's answer.
            return UserDefaults.standard.string(forKey: key.rawValue) ?? ""
        }
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        return cache[key.rawValue] ?? ""
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
        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()
        guard !vaultUnreadable else {
            // The vault exists but could not be decrypted (missing or refused master key).
            // Writing now would replace values we cannot see, so the write is dropped instead.
            AppLogger.error(
                "Refusing to write \(key.rawValue): the credential vault is unreadable",
                logger: AppLogger.data
            )
            return
        }
        var values = cache
        values[key.rawValue] = trimmed
        persistLocked(values)
    }

    static func clear(_ key: SecretKey) {
        if isApp {
            lock.lock()
            ensureLoadedLocked()
            if !vaultUnreadable {
                var values = cache
                values.removeValue(forKey: key.rawValue)
                persistLocked(values)
            } else {
                cache.removeValue(forKey: key.rawValue)
            }
            lock.unlock()
            deleteLegacyItem(key)
        }
        // Always clear the defaults copy too: a stale one would be migrated back on next launch.
        UserDefaults.standard.removeObject(forKey: key.rawValue)
    }

    static func clearAll() {
        if isApp {
            lock.lock()
            didLoad = true
            cache.removeAll()
            vaultUnreadable = false
            lock.unlock()

            try? FileManager.default.removeItem(at: vault.fileURL)
            SecretKey.allCases.forEach(deleteLegacyItem)
            deleteMasterKeyItem()
        }
        SecretKey.allCases.forEach { UserDefaults.standard.removeObject(forKey: $0.rawValue) }
    }

    /// Moves credentials written by a build that stored them in `UserDefaults` into the vault, then
    /// deletes the plaintext copies. Safe to call on every launch: it only acts on a non-empty
    /// defaults value, and only after the vault reads the value back.
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
            if value(for: key).isEmpty {
                set(trimmed, for: key)
                guard value(for: key) == trimmed else {
                    AppLogger.error(
                        "Vault migration for \(key.rawValue) did not read back; leaving the defaults copy in place",
                        logger: AppLogger.data
                    )
                    continue
                }
                moved += 1
            }
            defaults.removeObject(forKey: key.rawValue)
        }
        if moved > 0 {
            AppLogger.info("Moved \(moved) credential(s) from UserDefaults into the vault", logger: AppLogger.data)
        }
    }

    // MARK: - Environment

    /// True only inside one of the app bundles. The dev bundle gets its own vault file, master key
    /// item and legacy service, so the two never read each other's data.
    private static var bundleID: String? { Bundle.main.bundleIdentifier }

    private static var isApp: Bool {
        bundleID == "com.vara.mediatracker" || bundleID == "com.vara.mediatracker.dev"
    }

    /// Master key item created by this build.
    private static var masterKeyService: String {
        "\(bundleID ?? "com.vara.mediatracker").vault"
    }

    /// Per-key items written by builds before the vault existed.
    private static var legacyService: String {
        "\(bundleID ?? "com.vara.mediatracker").credentials"
    }

    // MARK: - State

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: String] = [:]
    private nonisolated(unsafe) static var didLoad = false
    /// The vault file exists but its master key was missing or refused. Empty `cache` is
    /// ambiguous on its own, and the two cases must never be treated alike: "empty" means a
    /// credential can be created, "unreadable" means one exists that we were not allowed to see.
    private nonisolated(unsafe) static var vaultUnreadable = false

    private static let keyLock = NSLock()
    private nonisolated(unsafe) static var masterKeyCache: Data?

    /// All access goes through `lock`, which is what makes the shared vault safe.
    private nonisolated(unsafe) static let vault: CredentialVault = {
        let directory: URL
        do {
            directory = try StoreLocation.dataDirectory()
        } catch {
            AppLogger.error("Credential vault directory unavailable: \(error)", logger: AppLogger.data)
            directory = FileManager.default.temporaryDirectory
        }
        return CredentialVault(
            fileURL: directory.appendingPathComponent(CredentialVault.fileName),
            keyProvider: { try keychainMasterKey(createIfMissing: $0) }
        )
    }()

    /// Test seam, matching `ImageCache.configureForTesting`. Empties the cache so the next read goes
    /// back to the store — used when a test changes the defaults a fixture was seeded with.
    static func invalidateCache() {
        lock.lock()
        cache.removeAll()
        didLoad = false
        vaultUnreadable = false
        lock.unlock()
    }

    // MARK: - Load and migrate

    private static func ensureLoadedLocked() {
        guard !didLoad else { return }
        didLoad = true

        switch vault.load() {
        case .loaded(let values):
            cache = values

        case .missing:
            // No vault yet: this is where builds that stored credentials per key (Keychain) are
            // folded in. Nothing is deleted unless the new file reads back identically.
            switch readLegacyValues() {
            case .none:
                break
            case .refused:
                vaultUnreadable = true
            case .values(let legacy):
                do {
                    if try vault.importIfMissing(legacy) {
                        deleteLegacyItems()
                        AppLogger.info(
                            "Migrated \(legacy.count) credential(s) from the Keychain into the vault",
                            logger: AppLogger.data
                        )
                    }
                    cache = legacy
                } catch {
                    // The legacy items are still the only readable copy, so they stay.
                    AppLogger.error(
                        "Credential vault migration failed: \(error); legacy Keychain items left in place",
                        logger: AppLogger.data
                    )
                    cache = legacy
                }
            }

        case .unreadable:
            vaultUnreadable = true
        }
    }

    private static func persistLocked(_ values: [String: String]) {
        do {
            try vault.save(values)
            cache = values
            vaultUnreadable = false
        } catch {
            AppLogger.error("Failed to write the credential vault: \(error)", logger: AppLogger.data)
        }
    }

    // MARK: - Signing identity

    private static let identityDefaultsKey = "keychain_owning_requirement"

    /// This binary's designated requirement, as text.
    ///
    /// It changes when the app is re-signed by a different identity — an ad-hoc rebuild, or a switch
    /// between certificates — and it is what a Keychain ACL records when the app creates an item.
    static func currentSigningRequirement() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess,
              let text else { return nil }
        return text as String
    }

    /// Re-writes the master key item when this binary was signed by a different identity.
    ///
    /// A Keychain item's ACL names the designated requirement of the app that created it. If this
    /// binary has a different one — the item predates the stable certificate, or was written by an
    /// ad-hoc build — reading asks for approval, and "Allow" only answers that one read. The ACL is
    /// repaired by deleting and re-adding the item under this binary, which requires the key bytes,
    /// so this is a no-op (retried later) when the key cannot be read.
    ///
    /// The vault file needs no changes: it is encrypted with the key, not with the ACL.
    static func adoptIfSigningIdentityChanged() {
        guard isApp, let current = currentSigningRequirement() else { return }
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: identityDefaultsKey) != current else { return }

        do {
            let key = try keychainMasterKey(createIfMissing: false)
            try rewriteMasterKeyItem(key)
            defaults.set(current, forKey: identityDefaultsKey)
            AppLogger.info("Re-adopted the vault key under the current signing identity", logger: AppLogger.data)
        } catch CredentialVault.VaultError.keyRefused {
            AppLogger.info("Vault key access was refused; re-adoption will retry", logger: AppLogger.data)
        } catch {
            AppLogger.error("Vault key re-adoption failed: \(error)", logger: AppLogger.data)
        }
    }

    /// Whether this credential is present, answered without decrypting more than the vault
    /// already needs to be.
    ///
    /// Callers use this to distinguish "no credential yet" from "a vault exists but could not be
    /// read"; the second must never be treated as the first. It must also answer for the *given
    /// key* — a vault that exists but no longer contains the sync key means "not configured".
    static func hasItem(_ key: SecretKey) -> Bool {
        guard isApp else { return !value(for: key).isEmpty }

        lock.lock()
        defer { lock.unlock() }
        ensureLoadedLocked()

        if vaultUnreadable {
            // We cannot tell what is inside, but something is there. Reporting "absent" here
            // would let callers overwrite a credential they simply could not read.
            return vault.exists
        }
        if vault.exists {
            return !(cache[key.rawValue] ?? "").isEmpty
        }
        return legacyItemExists(key)
    }

    // MARK: - Master key (Keychain)

    private static func keychainMasterKey(createIfMissing: Bool) throws -> Data {
        keyLock.lock()
        defer { keyLock.unlock() }

        if let cached = masterKeyCache { return cached }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyService,
            kSecAttrAccount as String: "master-key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, data.count == CredentialVault.keyLength else {
                throw CredentialVault.VaultError.invalidKey
            }
            masterKeyCache = data
            return data

        case errSecItemNotFound:
            // Creating a key when the vault exists would make the existing ciphertext
            // permanently undecryptable, so reads never generate one.
            guard createIfMissing else { throw CredentialVault.VaultError.keyUnavailable }
            let key = try randomMasterKey()
            try addMasterKeyItem(key)
            masterKeyCache = key
            return key

        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw CredentialVault.VaultError.keyRefused

        default:
            AppLogger.error("Master key read failed: \(status)", logger: AppLogger.data)
            throw CredentialVault.VaultError.keyUnavailable
        }
    }

    private static func randomMasterKey() throws -> Data {
        var bytes = Data(count: CredentialVault.keyLength)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            AppLogger.error("Master key generation failed: \(status)", logger: AppLogger.data)
            throw CredentialVault.VaultError.keyUnavailable
        }
        return bytes
    }

    /// Caller holds `keyLock`.
    private static func addMasterKeyItem(_ key: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyService,
            kSecAttrAccount as String: "master-key",
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            AppLogger.error("Master key add failed: \(status)", logger: AppLogger.data)
            throw CredentialVault.VaultError.keyUnavailable
        }
    }

    private static func rewriteMasterKeyItem(_ key: Data) throws {
        keyLock.lock()
        defer { keyLock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyService,
            kSecAttrAccount as String: "master-key"
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw CredentialVault.VaultError.writeFailed("master key delete failed: \(deleteStatus)")
        }
        try addMasterKeyItem(key)
        masterKeyCache = key
    }

    private static func deleteMasterKeyItem() {
        keyLock.lock()
        defer { keyLock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: masterKeyService,
            kSecAttrAccount as String: "master-key"
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.error("Master key delete failed: \(status)", logger: AppLogger.data)
        }
        masterKeyCache = nil
    }

    // MARK: - Legacy per-key Keychain items

    private enum LegacyRead {
        case none
        case values([String: String])
        /// At least one read was refused, so the set is untrustworthy and nothing may be deleted.
        case refused
    }

    private static func legacyBaseQuery(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: key.rawValue
        ]
    }

    private static func readLegacyValues() -> LegacyRead {
        var values: [String: String] = [:]
        for key in SecretKey.allCases {
            var query = legacyBaseQuery(key)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            switch status {
            case errSecSuccess:
                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8),
                   !string.isEmpty {
                    values[key.rawValue] = string
                }
            case errSecItemNotFound:
                continue
            case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
                return .refused
            default:
                AppLogger.error("Legacy keychain read for \(key.rawValue) failed: \(status)", logger: AppLogger.data)
            }
        }
        return values.isEmpty ? .none : .values(values)
    }

    private static func legacyItemExists(_ key: SecretKey) -> Bool {
        var query = legacyBaseQuery(key)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess
    }

    private static func deleteLegacyItems() {
        SecretKey.allCases.forEach(deleteLegacyItem)
    }

    private static func deleteLegacyItem(_ key: SecretKey) {
        let status = SecItemDelete(legacyBaseQuery(key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            AppLogger.error("Legacy keychain delete for \(key.rawValue) failed: \(status)", logger: AppLogger.data)
        }
    }
}
