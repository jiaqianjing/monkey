import Foundation
import Security

/// Classic macOS Keychain ACL prompts do not consistently honor the SecItem
/// per-query authentication flags. Serialize all Monkey Keychain operations so
/// a scoped, process-local no-UI setting cannot race explicit authorization.
/// This only restricts UI: it never grants access, changes an ACL or unlocks a Keychain.
final class KeychainOperationQueue: @unchecked Sendable {
    private let queue: DispatchQueue
    private let getInteractionAllowed: () throws -> Bool
    private let setInteractionAllowed: (Bool) throws -> Void

    init(
        label: String = "org.monkey.inputmethod.keychain",
        getInteractionAllowed: @escaping () throws -> Bool = {
            var allowed = DarwinBoolean(false)
            let status = SecKeychainGetUserInteractionAllowed(&allowed)
            guard status == errSecSuccess else { throw KeychainAccessError(status: status) }
            return allowed.boolValue
        },
        setInteractionAllowed: @escaping (Bool) throws -> Void = { allowed in
            let status = SecKeychainSetUserInteractionAllowed(allowed)
            guard status == errSecSuccess else { throw KeychainAccessError(status: status) }
        }
    ) {
        queue = DispatchQueue(label: label, qos: .userInitiated)
        self.getInteractionAllowed = getInteractionAllowed
        self.setInteractionAllowed = setInteractionAllowed
    }

    func perform<T: Sendable>(allowAuthenticationUI: Bool, operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if allowAuthenticationUI {
                        // Do not forcibly enable UI if another caller already
                        // restricted it. Explicit authorization respects prior policy.
                        continuation.resume(returning: try operation())
                        return
                    }
                    let previous = try getInteractionAllowed()
                    try setInteractionAllowed(false)
                    // Capture either result before restoring the exact old policy.
                    // Restoration errors are surfaced and no subsequent operation
                    // can enter this queue before restoration was attempted.
                    let result = Result { try operation() }
                    try setInteractionAllowed(previous)
                    continuation.resume(with: result)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
}
