import Foundation
import Security

/// Stable per-device UUID stored in the Keychain. Survives app uninstall via
/// keychain access groups (with default behavior the value clears on a full
/// device reset). Used as the `clientId` argument on every Convex call until
/// proper auth lands.
enum ClientIdentity {
    private static let service = "com.binsight.clientId"
    private static let account = "default"

    static var current: String {
        if let existing = read() { return existing }
        let fresh = UUID().uuidString
        write(fresh)
        return fresh
    }

    private static func read() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String) {
        let data = Data(value.utf8)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}
