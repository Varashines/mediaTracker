import CryptoKit
import XCTest
@testable import MediaTracker

final class CredentialVaultTests: XCTestCase {
    private var directory: URL!
    private let keyA = Data(repeating: 0x11, count: CredentialVault.keyLength)
    private let keyB = Data(repeating: 0x22, count: CredentialVault.keyLength)

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("credential-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    private var fileURL: URL { directory.appendingPathComponent(CredentialVault.fileName) }

    private func vault(key: Data) -> CredentialVault {
        CredentialVault(fileURL: fileURL) { _ in key }
    }

    private func vault(error: CredentialVault.VaultError) -> CredentialVault {
        CredentialVault(fileURL: fileURL) { _ in throw error }
    }

    private var corruptFiles: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.contains(".corrupt-") } ?? []
    }

    // MARK: - Round trip

    func testRoundTripPreservesEveryValue() throws {
        let values = [
            SecretKey.tmdb.rawValue: "tmdb-key",
            SecretKey.cloudSyncKey.rawValue: "sync-secret",
            SecretKey.cloudSyncAnonKey.rawValue: "anon",
        ]
        try vault(key: keyA).save(values)

        XCTAssertEqual(vault(key: keyA).load(), .loaded(values))
    }

    func testEmptyVaultRoundTrips() throws {
        try vault(key: keyA).save([:])
        XCTAssertEqual(vault(key: keyA).load(), .loaded([:]))
    }

    func testVaultFileIsCiphertextOnDisk() throws {
        try vault(key: keyA).save([SecretKey.cloudSyncKey.rawValue: "SUPER-SECRET-SYNC-KEY"])

        let raw = try Data(contentsOf: fileURL)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("SUPER-SECRET-SYNC-KEY"))
    }

    func testSaveIsReadableWithFilePermissions600() throws {
        try vault(key: keyA).save([:])
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    // MARK: - Failure handling

    private func assertUnreadable(
        _ outcome: CredentialVault.LoadOutcome,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .unreadable = outcome else {
            XCTFail("expected unreadable, got \(outcome)", file: file, line: line)
            return
        }
    }

    func testWrongKeyIsUnreadableAndMovesTheFileAside() throws {
        try vault(key: keyA).save([SecretKey.tmdb.rawValue: "tmdb-key"])

        assertUnreadable(vault(key: keyB).load(), "wrong key")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "the unusable vault must not stay in place")
        XCTAssertEqual(corruptFiles.count, 1, "it must be kept, not deleted")
    }

    func testMissingKeyLeavesTheVaultInPlace() throws {
        try vault(key: keyA).save([SecretKey.tmdb.rawValue: "tmdb-key"])

        assertUnreadable(vault(error: .keyUnavailable).load(), "missing key")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(corruptFiles.isEmpty, "a missing key is recoverable and must not quarantine")
    }

    func testRefusedKeyLeavesTheVaultInPlace() throws {
        try vault(key: keyA).save([SecretKey.tmdb.rawValue: "tmdb-key"])

        assertUnreadable(vault(error: .keyRefused).load(), "refused key")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertTrue(corruptFiles.isEmpty)
    }

    func testMissingFileIsReportedAsMissing() {
        XCTAssertEqual(vault(key: keyA).load(), .missing)
    }

    func testTruncatedFileIsQuarantined() throws {
        try Data("not a vault".utf8).write(to: fileURL)

        assertUnreadable(vault(key: keyA).load(), "malformed envelope")
        XCTAssertEqual(corruptFiles.count, 1)
    }

    func testSaveRejectsAKeyOfTheWrongLength() {
        let shortKey = Data(repeating: 0x01, count: 16)
        XCTAssertThrowsError(try vault(key: shortKey).save([:])) { error in
            XCTAssertEqual(error as? CredentialVault.VaultError, .invalidKey)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Legacy import

    func testImportWritesOnlyWhenNoVaultExists() throws {
        let legacy = [SecretKey.tmdb.rawValue: "legacy-tmdb"]
        let target = vault(key: keyA)

        XCTAssertTrue(try target.importIfMissing(legacy))
        XCTAssertEqual(target.load(), .loaded(legacy))
        XCTAssertFalse(try target.importIfMissing(legacy), "a second import must not run")
    }

    func testImportRefusesToOverwriteAnExistingVault() throws {
        try vault(key: keyA).save([SecretKey.tmdb.rawValue: "current"])

        let imported = try vault(key: keyA).importIfMissing([SecretKey.tmdb.rawValue: "legacy"])
        XCTAssertFalse(imported)
        XCTAssertEqual(vault(key: keyA).load(), .loaded([SecretKey.tmdb.rawValue: "current"]))
    }

    func testImportIgnoresEmptyLegacyValues() throws {
        XCTAssertFalse(try vault(key: keyA).importIfMissing([:]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testImportIsReadBackBeforeReportingSuccess() throws {
        // A key provider that yields a different key on the read-back makes verification
        // fail; the import must throw rather than leave a vault nobody can decrypt.
        var calls = 0
        let flaky = CredentialVault(fileURL: fileURL) { _ in
            calls += 1
            return calls == 1 ? self.keyA : self.keyB
        }

        XCTAssertThrowsError(try flaky.importIfMissing([SecretKey.tmdb.rawValue: "legacy"]))
    }
}
