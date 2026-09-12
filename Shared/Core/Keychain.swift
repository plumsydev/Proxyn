import Foundation
import Security

/// Minimal Keychain wrapper. Passwords and token secrets never touch
/// UserDefaults.
///
/// Items are written to the app group's access group so the widget extension
/// can read them (on iOS an app group identifier doubles as a keychain access
/// group). When that entitlement isn't provisioned — a bare development
/// profile, or `swift test` on macOS — it falls back to the default access
/// group rather than failing to save.
enum Keychain {
    static let service = "com.proxyn.credentials"
    static let sharedAccessGroup = AppGroup.identifier

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        for group in [sharedAccessGroup, nil] as [String?] {
            var query = baseQuery(key: key, group: group)
            SecItemDelete(query as CFDictionary)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

            let status = SecItemAdd(query as CFDictionary, nil)
            if status == errSecSuccess { return true }
            if status != errSecMissingEntitlement {
                Log.keychain.error("SecItemAdd failed: \(status, privacy: .public)")
                return false
            }
        }
        return false
    }

    static func get(_ key: String) -> String? {
        for group in [sharedAccessGroup, nil] as [String?] {
            var query = baseQuery(key: key, group: group)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    @discardableResult
    static func remove(_ key: String) -> Bool {
        var removed = true
        for group in [sharedAccessGroup, nil] as [String?] {
            let status = SecItemDelete(baseQuery(key: key, group: group) as CFDictionary)
            if status != errSecSuccess, status != errSecItemNotFound, status != errSecMissingEntitlement {
                removed = false
            }
        }
        return removed
    }

    private static func baseQuery(key: String, group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }
}
