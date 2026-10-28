import Foundation

/// Shared by the input-method service and its settings window. An unset value
/// defaults to enabled, while an explicitly saved false value stays disabled.
public enum TypingPreferences {
    public static let defaults = UserDefaults(suiteName: "org.monkey.inputmethod.shared")!

    public static var automaticEnglish: Bool {
        get { enabledByDefault("typing.automaticEnglish") }
        set { defaults.set(newValue, forKey: "typing.automaticEnglish") }
    }

    public static var horizontalCandidates: Bool {
        get { enabledByDefault("typing.horizontalCandidates") }
        set { defaults.set(newValue, forKey: "typing.horizontalCandidates") }
    }

    public static var englishSpaceInsertsSpace: Bool {
        get { enabledByDefault("typing.englishSpaceInsertsSpace") }
        set { defaults.set(newValue, forKey: "typing.englishSpaceInsertsSpace") }
    }

    private static func enabledByDefault(_ key: String) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}
