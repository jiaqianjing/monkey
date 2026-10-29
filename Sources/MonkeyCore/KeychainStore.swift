import Foundation
import LocalAuthentication
import Security

/// Credentials are scoped to Monkey, never imported from another application.
enum KeychainStore {
    static let service = "org.monkey.inputmethod"
    private static let operations = KeychainOperationQueue()

    private static func read<T: Decodable>(_ type: T.Type, account: String, allowAuthenticationUI: Bool) throws -> T? {
        var query = base(account)
        if !allowAuthenticationUI { preventAuthenticationUI(in: &query) }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw error(status) }
        return try JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, account: String, allowAuthenticationUI: Bool) throws {
        let data = try JSONEncoder().encode(value)
        var lookup = base(account)
        if !allowAuthenticationUI { preventAuthenticationUI(in: &lookup) }
        let status = SecItemUpdate(lookup as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = base(account)
            if !allowAuthenticationUI { preventAuthenticationUI(in: &query) }
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw error(added) }
        } else if status != errSecSuccess { throw error(status) }
    }

    private static func delete(account: String) throws {
        let status = SecItemDelete(base(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }

    // Keychain Services is synchronous and may wait for system authorization.
    // Never block the input-method's main actor while waiting for it.
    static func readAsync<T: Decodable & Sendable>(_ type: T.Type, account: String, allowAuthenticationUI: Bool = false) async throws -> T? {
        try await operations.perform(allowAuthenticationUI: allowAuthenticationUI) {
            try read(type, account: account, allowAuthenticationUI: allowAuthenticationUI)
        }
    }

    static func writeAsync<T: Encodable & Sendable>(_ value: T, account: String, allowAuthenticationUI: Bool = true) async throws {
        try await operations.perform(allowAuthenticationUI: allowAuthenticationUI) {
            try write(value, account: account, allowAuthenticationUI: allowAuthenticationUI)
        }
    }

    static func deleteAsync(account: String) async throws {
        try await operations.perform(allowAuthenticationUI: true) { try delete(account: account) }
    }

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func preventAuthenticationUI(in query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        // Existing connections live in the classic login Keychain. Keep its
        // explicit no-UI option as well as LAContext until migration to a
        // provisioned data-protection Keychain is possible. No ACL is widened.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    }

    private static func error(_ status: OSStatus) -> Error {
        KeychainAccessError(status: status)
    }
}

struct KeychainAccessError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? {
        "无法读取 Monkey 的钥匙串连接（\(status)）。请打开 Monkey 设置，点击“允许钥匙串访问”；中文原文已保留。"
    }
}
