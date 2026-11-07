import CryptoKit
import Foundation

/// A single encrypted file holding every credential, unlocked by one Keychain-held key.
///
/// ## Why a vault rather than one Keychain item per secret
///
/// Five separate items mean five ACLs: when the app's signing identity changes, every
/// item needs its own approval, and a machine backup carries five opaque blobs. Here the
/// ACL applies to one 32-byte master key, the secrets are ciphertext on disk, and the
/// payload moves as a single file.
///
/// This does not remove the Keychain dependency. The master key still lives there, and
/// that is exactly what makes the encrypted file useless to another process. The vault
/// changes how many items participate, not whether the OS guards them.
///
/// ## What is on disk
///
/// `credentials.vault` is a JSON envelope holding a version and the AES-GCM combined box
/// (nonce + ciphertext + tag). Without the master key it is indistinguishable from random
/// bytes, and a single flipped byte fails authentication instead of decrypting to garbage.
///
/// ## Failure handling
///
/// An unreadable envelope is moved aside rather than overwritten: the file may be the only
/// copy of a sync key, and a failed read must never be answered by deleting it. A missing
/// or refused master key is reported as `.unreadable` and leaves the file untouched, so
/// restoring the Keychain item makes the vault readable again.
struct CredentialVault {
    enum LoadOutcome: Equatable {
        case loaded([String: String])
        case missing
        case unreadable(reason: String)
    }

    enum VaultError: Error, Equatable {
        case keyUnavailable
        case keyRefused
        case invalidKey
        case writeFailed(String)
    }

    /// Returns the 32-byte master key.
    ///
    /// `createIfMissing` is false on reads on purpose: silently generating a new key
    /// would leave the existing ciphertext permanently undecryptable, so a missing key
    /// must be reported instead of papered over.
    typealias KeyProvider = (_ createIfMissing: Bool) throws -> Data

    static let fileName = "credentials.vault"
    static let keyLength = 32

    let fileURL: URL
    private let keyProvider: KeyProvider
    private let fileManager: FileManager

    init(fileURL: URL, keyProvider: @escaping KeyProvider, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.keyProvider = keyProvider
        self.fileManager = fileManager
    }

    var exists: Bool { fileManager.fileExists(atPath: fileURL.path) }

    func load() -> LoadOutcome {
        guard exists else { return .missing }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: try Data(contentsOf: fileURL))
        } catch {
            return unreadable("envelope could not be read (\(error))", quarantine: true)
        }
        guard envelope.version == Envelope.currentVersion else {
            return unreadable("unsupported vault version \(envelope.version)", quarantine: false)
        }

        let key: Data
        do {
            key = try keyProvider(false)
        } catch VaultError.keyRefused {
            return unreadable("master key access refused", quarantine: false)
        } catch {
            return unreadable("master key unavailable", quarantine: false)
        }
        guard key.count == Self.keyLength else {
            return unreadable("master key has the wrong length", quarantine: false)
        }

        do {
            let box = try AES.GCM.SealedBox(combined: envelope.sealed)
            let plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key))
            let values = try JSONDecoder().decode([String: String].self, from: plaintext)
            return .loaded(values)
        } catch {
            // Authentication failed or the plaintext is not the expected shape. Both mean
            // the file cannot be trusted, so it is kept aside instead of overwritten.
            return unreadable("authentication failed (\(error))", quarantine: true)
        }
    }

    /// Encrypts and writes atomically: a failed write leaves the previous vault intact.
    func save(_ values: [String: String]) throws {
        let key: Data
        do {
            key = try keyProvider(true)
        } catch {
            throw error
        }
        guard key.count == Self.keyLength else { throw VaultError.invalidKey }

        let plaintext = try JSONEncoder().encode(values)
        guard let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key)).combined else {
            throw VaultError.writeFailed("AES-GCM produced no combined representation")
        }
        let data = try JSONEncoder().encode(Envelope(version: Envelope.currentVersion, sealed: sealed))

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw VaultError.writeFailed("\(error)")
        }
        // The payload is ciphertext, but 0600 still keeps other users out of the file.
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    /// Imports legacy per-key Keychain values, but only when no vault exists yet and only
    /// after a read-back proves the new file decrypts to exactly those values. Returns
    /// true when an import was performed.
    ///
    /// The caller deletes the legacy items only after this returns true.
    @discardableResult
    func importIfMissing(_ legacy: [String: String]) throws -> Bool {
        guard !exists, !legacy.isEmpty else { return false }
        try save(legacy)
        guard case .loaded(let readBack) = load(), readBack == legacy else {
            throw VaultError.writeFailed("vault read-back did not match the imported values")
        }
        return true
    }

    // MARK: - Helpers

    private func unreadable(_ reason: String, quarantine: Bool) -> LoadOutcome {
        guard quarantine else {
            AppLogger.error("Credential vault unreadable: \(reason)", logger: AppLogger.data)
            return .unreadable(reason: reason)
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let target = fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(Self.fileName).corrupt-\(stamp)")
        do {
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            try fileManager.moveItem(at: fileURL, to: target)
            AppLogger.error(
                "Credential vault unreadable (\(reason)); moved aside to \(target.lastPathComponent)",
                logger: AppLogger.data
            )
        } catch {
            AppLogger.error(
                "Credential vault unreadable (\(reason)) and could not be moved aside: \(error)",
                logger: AppLogger.data
            )
        }
        return .unreadable(reason: reason)
    }

    private struct Envelope: Codable {
        static let currentVersion = 1
        let version: Int
        let sealed: Data
    }
}
