import Foundation

/// Forget a registration only after its protected credentials have been deleted.
/// Other accounts and this Mac's host identity remain independent of the removal.
@MainActor
enum ChatGPTConnectionRemoval {
    @discardableResult
    static func remove(
        _ clientID: String,
        from defaults: UserDefaults,
        domain: String = "org.monkey.inputmethod.shared",
        deleteCredential: () async throws -> Void
    ) async throws -> Bool {
        // Credential deletion occurs under the caller's per-client lock. Do not
        // hold the metadata lock across Keychain UI or any asynchronous work.
        guard try ChatGPTAccountMetadata.withLock(defaults: defaults, domain: domain, { try ChatGPTAccountMetadata.accounts(defaults).contains { $0.clientID == clientID } }) else { return false }
        try await deleteCredential()
        return try ChatGPTAccountMetadata.withLock(defaults: defaults, domain: domain) {
            let remaining = try ChatGPTAccountMetadata.accounts(defaults).filter { $0.clientID != clientID }
            let encoded = try JSONEncoder().encode(remaining)
            let wasActive = defaults.string(forKey: "ChatGPT.activeClientID") == clientID
            defaults.set(encoded, forKey: "ChatGPT.accounts")
            defaults.removeObject(forKey: "ChatGPT.credentialRevision.\(clientID)")
            ChatGPTAccountMetadata.setDisabled(clientID, disabled: false, defaults: defaults)
            if wasActive {
                defaults.removeObject(forKey: "ChatGPT.activeClientID")
                defaults.removeObject(forKey: "ChatGPT.selectedModel")
            }
            if defaults.string(forKey: "ChatGPT.pendingClientID") == clientID {
                defaults.removeObject(forKey: "ChatGPT.pendingClientID")
            }
            return wasActive
        }
    }
}
