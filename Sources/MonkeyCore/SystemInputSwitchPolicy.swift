import Foundation

/// A deliberately narrow signal for the system input-source switch path.
/// Source and foreground app are observations, not proof of the user's intent.
public enum SystemInputSwitchPolicy {
    public static func shouldCommitRaw(
        active: Bool,
        observedMonkeySource: Bool,
        isASCIICapableKeyboardLayout: Bool,
        activationProcessID: Int32?,
        currentProcessID: Int32?
    ) -> Bool {
        guard active, observedMonkeySource, isASCIICapableKeyboardLayout,
              let activationProcessID, let currentProcessID else { return false }
        return activationProcessID == currentProcessID
    }
}
