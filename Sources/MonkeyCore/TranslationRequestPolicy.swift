import Foundation

/// Only opt into low-latency reasoning for the exact model whose official
/// capability page documents `none`. Unknown models keep their own defaults.
public enum TranslationRequestPolicy {
    @MainActor public static var preferSpeed: Bool {
        get { ChatGPTClient.defaults.object(forKey: "translation.preferSpeed") == nil || ChatGPTClient.defaults.bool(forKey: "translation.preferSpeed") }
        set { ChatGPTClient.defaults.set(newValue, forKey: "translation.preferSpeed") }
    }

    public static func reasoningEffort(model: String, preferSpeed: Bool) -> String? {
        guard preferSpeed, model == "gpt-6.1-terra" else { return nil }
        return "none"
    }
}
