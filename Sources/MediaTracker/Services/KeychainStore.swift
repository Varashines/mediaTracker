import Foundation
import Security

/// Thin wrapper over the macOS Keychain for storing user-supplied API keys.
/// Keys are stored as generic passwords under a single service, one account per
/// key (using the same identifiers as the legacy UserDefaults keys), so nothing
/// secrets-shaped lives in plaintext preferences.
enum KeychainStore {
    private static let service = "com.vara.mediatracker.api-keys"

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    static func write(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Moves the legacy UserDefaults API keys into the Keychain. Runs once at
    /// launch; idempotent. Also clears any stray legacy values that were never
    /// migrated (e.g. from a downgrade or a reset that skipped the Keychain).
    static func migrateLegacyKeys() {
        let legacyKeys = [
            UserDefaultsKeys.tmdbAPIKey.rawValue,
            UserDefaultsKeys.omdbAPIKey.rawValue,
            UserDefaultsKeys.mmAPIKey.rawValue
        ]
        for key in legacyKeys {
            if read(key) == nil {
                if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
                    write(value, forKey: key)
                }
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
