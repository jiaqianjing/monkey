import Foundation
import Security

/// Credentials are scoped to Monkey, never imported from another application.
enum KeychainStore {
    static let service = "org.monkey.inputmethod"

    static func read<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw error(status) }
        return try JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let status = SecItemUpdate(base(account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = base(account)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw error(added) }
        } else if status != errSecSuccess { throw error(status) }
    }

    static func delete(account: String) throws {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func error(_ status: OSStatus) -> Error {
        ChatGPTError.message("无法访问 Monkey 的钥匙串凭据（\(status)）。请在系统提示中允许访问。")
    }
}
