import Foundation
import Security

/// One-time migration helper: copies any API keys previously saved in the
/// Keychain back into UserDefaults (keys now live in UserDefaults again, matching
/// the app's pre-Keychain behavior).
enum KeychainStore {
    private static let service = "com.vara.mediatracker.api-keys"

    /// Restores keys from the Keychain into UserDefaults, then removes the
    /// Keychain items. Safe to call on every launch — only fills empty slots.
    static func restoreToUserDefaults() {
        let keys = [
            UserDefaultsKeys.tmdbAPIKey.rawValue,
            UserDefaultsKeys.omdbAPIKey.rawValue,
            UserDefaultsKeys.mmAPIKey.rawValue
        ]
        for key in keys {
            if (UserDefaults.standard.string(forKey: key) ?? "").isEmpty,
               let value = read(key), !value.isEmpty {
                UserDefaults.standard.set(value, forKey: key)
            }
            delete(key)
        }
    }

    private static func read(_ key: String) -> String? {
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

    private static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
