import Foundation

/// Classification of one uncommitted token. Chinese text is deliberately left
/// to the pinyin engine unless an explicit URL/path prefix establishes a literal.
public enum MixedInputKind: String, Codable, Sendable {
    case pinyin, english, url, email, filePath, number, version

    public var isStructuredLiteral: Bool {
        switch self {
        case .url, .email, .filePath, .number, .version: return true
        case .pinyin, .english: return false
        }
    }
}

/// Conservative, entirely local decisions for mixed Chinese/ASCII input.
///
/// The caller owns its actual raw keystroke buffer and the composition lifecycle.
/// Enter should commit that raw buffer verbatim. `candidate(for:)` is only an
/// optional candidate: it must not replace or silently commit pinyin candidates.
public enum MixedInputPolicy {
    public static func classify(_ buffer: String) -> MixedInputKind {
        guard !buffer.isEmpty, !buffer.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) else { return .pinyin }
        let lower = buffer.lowercased()
        if schemes.contains(where: { lower.hasPrefix($0 + ":") }) { return .url }
        if lower.hasPrefix("www.") || isBareDomain(buffer) { return .url }
        if buffer.hasPrefix("/") || buffer.hasPrefix("~/") || buffer.hasPrefix("./") || buffer.hasPrefix("../") || matches(windowsPath, buffer) || isKnownRelativePath(buffer) {
            return .filePath
        }
        guard isASCIIToken(buffer) else { return .pinyin }
        if matches(email, buffer) { return .email }
        if matches(version, buffer) { return .version }
        if matches(number, buffer) || matches(timeOrDate, buffer) { return .number }
        if knownEnglishCandidate(buffer) != nil { return .english }
        return .pinyin
    }

    /// Standard spelling for a known English token, or the exact source for a
    /// structured literal. Explicit user capitalization is always preserved.
    /// Unknown text, pinyin abbreviations, and merely mixed-case text return nil.
    public static func candidate(for buffer: String) -> String? {
        let kind = classify(buffer)
        if kind.isStructuredLiteral { return buffer }
        return knownEnglishCandidate(buffer)
    }

    /// Whether the next key gives strong enough evidence to start a literal
    /// composition instead of allowing Rime to consume punctuation or a digit.
    /// Digits after ordinary pinyin remain candidate selection keys.
    ///
    /// A generic pinyin token followed by '.' is intentionally not treated as a
    /// website: `nihao.` must still produce Chinese text plus a Chinese full stop.
    /// Common bare website prefixes work directly; arbitrary domains work when
    /// entered with an explicit scheme or with the caller's raw-Enter operation.
    public static func shouldStartLiteral(buffer: String, next: Character, precedingText: String = "") -> Bool {
        guard let nextASCII = next.asciiValue, nextASCII >= 0x21, nextASCII <= 0x7e else { return false }
        if classify(buffer).isStructuredLiteral { return true }

        if buffer.isEmpty {
            if isDigit(nextASCII) { return true }
            if next == "/" { return true }
            if (next == "." || next == ":"), trailingNumericToken(in: precedingText) != nil { return true }
            return false
        }
        guard isASCIIToken(buffer) else { return false }
        let lower = buffer.lowercased()
        if next == "@", matches(emailLocalPart, buffer) { return true }
        if next == ":", schemes.contains(lower) { return true }
        if next == ".", lower == "www" || (buffer == lower && commonDomainPrefixes.contains(lower)) { return true }
        if next == "/", [".", "..", "~"].contains(buffer) || pathPrefixes.contains(lower) { return true }
        if isDigit(nextASCII) {
            if lower == "v" { return true }
            if knownEnglishCandidate(buffer) != nil { return true }
        }
        if next == "_", knownEnglishCandidate(buffer) != nil { return true }
        if next == "+", lower == "c" || buffer == "C+" { return true }
        if next == "#", lower == "c" { return true }
        return false
    }

    /// Punctuation that is part of a recognized URL, address, path, number, or
    /// version must remain ASCII. A word like ChatGPT alone does not change the
    /// surrounding sentence's Chinese punctuation.
    public static func shouldKeepASCIIPunctuation(_ character: Character, in buffer: String, precedingText: String = "") -> Bool {
        guard let ascii = character.asciiValue, ascii >= 0x21, ascii <= 0x7e,
              !isASCIIAlpha(ascii), !isDigit(ascii) else { return false }
        let allowed: String
        switch classify(buffer) {
        case .url: allowed = ":/?#[]@!$&'()*+,;=%._-~"
        case .email: allowed = ".@_+-!#$%&'*=/^`{|}~"
        case .filePath: allowed = "/.\\_-~:+=@%()[]{}$!#&,;"
        case .number: allowed = ".:+-/%"
        case .version: allowed = ".+-_"
        case .english, .pinyin:
            if (character == "." || character == ":" || character == "%"),
               buffer.isEmpty, trailingNumericToken(in: precedingText) != nil { return true }
            return false
        }
        return allowed.contains(character)
    }

    // A small reviewed list is safer than using uppercase or invalid pinyin as
    // evidence of English. These are candidates, not a replacement dictionary.
    private static let standardEnglish: [String: String] = {
        let forms = [
            "ChatGPT", "OpenAI", "iPhone", "iPad", "iOS", "macOS", "MacBook", "AirPods", "Apple", "AppleScript",
            "GitHub", "GitLab", "VSCode", "SwiftUI", "Swift", "Xcode", "TestFlight", "AppStore", "Android", "Windows", "Linux",
            "Python", "JavaScript", "TypeScript", "Java", "Kotlin", "Rust", "Ruby", "PHP", "HTML", "CSS", "SQL", "SQLite",
            "PostgreSQL", "MySQL", "Redis", "Docker", "Kubernetes", "Node", "NodeJS", "React", "Vue", "NextJS", "Vite",
            "API", "SDK", "CLI", "JSON", "XML", "YAML", "CSV", "PDF", "URL", "HTTP", "HTTPS", "TCP", "UDP", "DNS", "SSH",
            "OAuth", "JWT", "UUID", "UTF8", "WiFi", "Bluetooth", "USB", "CPU", "GPU", "RAM", "SSD", "LLM", "GPT",
            "Claude", "Gemini", "DeepSeek", "Qwen", "Copilot", "Codex", "Chrome", "Safari", "Firefox", "Edge", "Notion",
            "Figma", "Slack", "Discord", "Telegram", "WhatsApp", "WeChat", "YouTube", "Gmail", "Outlook", "iCloud",
            "App", "hello", "world", "test", "email", "meeting", "code", "debug", "build", "release", "main", "master",
            "feature", "fix", "README", "TODO", "issue", "commit", "branch", "merge", "pull", "push", "copy", "paste",
            "file", "folder", "project", "workspace", "download", "upload", "login", "logout", "token", "model", "prompt",
            "server", "client", "npm", "git", "npmjs", "pypi", "localhost", "example", "google", "baidu", "bing"
        ]
        return Dictionary(forms.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    // Short tokens that are also useful pinyin must require explicit spelling.
    private static let caseSensitiveEnglish: Set<String> = ["AI", "UI", "UX", "Go", "R", "C", "C++", "C#"]
    private static let schemes: Set<String> = ["http", "https", "ftp", "file", "ssh", "ws", "wss", "mailto"]
    private static let commonDomainPrefixes: Set<String> = [
        "github", "gitlab", "google", "baidu", "bing", "openai", "chatgpt", "example", "localhost", "npmjs", "pypi",
        "huggingface", "apple", "developer.apple", "qq", "163", "126", "gmail", "icloud", "outlook", "yahoo",
        "wikipedia", "youtube", "bilibili", "douyin", "weixin", "weibo", "taobao", "jd", "zhihu", "v2ex",
        "stackoverflow", "vercel", "supabase", "notion", "figma", "reddit"
    ]
    private static let commonTLDs: Set<String> = [
        "com", "net", "org", "io", "dev", "app", "ai", "cn", "co", "me", "xyz", "tech", "site", "edu", "gov",
        "us", "uk", "de", "jp", "tv", "cc", "info", "biz", "cloud", "online", "store", "wiki", "design"
    ]
    private static let pathPrefixes: Set<String> = [
        "users", "applications", "library", "documents", "downloads", "desktop", "workspace", "sources", "tests",
        "src", "bin", "usr", "tmp", "etc", "opt", "var", "home"
    ]

    private static func knownEnglishCandidate(_ buffer: String) -> String? {
        guard isASCIIToken(buffer) else { return nil }
        if caseSensitiveEnglish.contains(buffer) { return buffer }
        let lower = buffer.lowercased()
        if let standard = standardEnglish[lower] { return buffer == lower ? standard : buffer }
        // Product/model suffixes are literal only after a complete known word.
        // A digit after nihao/nh must remain a Chinese candidate selection key.
        guard let digit = buffer.utf8.firstIndex(where: isDigit), digit > buffer.utf8.startIndex else { return nil }
        let prefix = String(decoding: buffer.utf8[..<digit], as: UTF8.self)
        let suffix = String(decoding: buffer.utf8[digit...], as: UTF8.self)
        guard suffix.utf8.allSatisfy({ isASCIIAlpha($0) || isDigit($0) || [45, 46, 43, 95].contains($0) }) else { return nil }
        let canonical = standardEnglish[prefix.lowercased()] ?? (caseSensitiveEnglish.contains(prefix) ? prefix : nil)
        guard let canonical else { return nil }
        return prefix == prefix.lowercased() ? canonical + suffix : buffer
    }

    private static func isBareDomain(_ buffer: String) -> Bool {
        let lower = buffer.lowercased()
        let host = lower.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" }
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.dropLast().allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ isASCIIAlpha($0) || isDigit($0) || $0 == 45 }) }) else { return false }
        let domainPrefix = components.dropLast().joined(separator: ".")
        if commonDomainPrefixes.contains(domainPrefix) {
            return components.last!.utf8.allSatisfy { isASCIIAlpha($0) || isDigit($0) || $0 == 45 }
        }
        return commonTLDs.contains(String(components.last!))
    }

    private static func isKnownRelativePath(_ buffer: String) -> Bool {
        guard let slash = buffer.firstIndex(of: "/"), slash != buffer.startIndex else { return false }
        return pathPrefixes.contains(buffer[..<slash].lowercased())
    }

    private static func trailingNumericToken(in text: String) -> String? {
        let suffix = String(text.reversed().prefix { "0123456789.:-+%".contains($0) }.reversed())
        guard !suffix.isEmpty, matches(number, suffix) || matches(timeOrDate, suffix) else { return nil }
        return suffix
    }

    private static func isASCIIToken(_ string: String) -> Bool {
        !string.isEmpty && string.utf8.allSatisfy { $0 >= 0x21 && $0 <= 0x7e }
    }
    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 48 && byte <= 57 }
    private static func isASCIIAlpha(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
    private static func matches(_ expression: NSRegularExpression, _ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
    private static let email = try! NSRegularExpression(pattern: "^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]*$")
    private static let emailLocalPart = try! NSRegularExpression(pattern: "^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+$")
    private static let windowsPath = try! NSRegularExpression(pattern: "^[A-Za-z]:[\\\\/].*$")
    private static let version = try! NSRegularExpression(pattern: "^[vV][0-9]+(?:\\.[0-9]*)*(?:[-+][0-9A-Za-z._-]*)?$")
    private static let number = try! NSRegularExpression(pattern: "^[+-]?(?:[0-9]+(?:\\.[0-9]*)*|\\.[0-9]+)%?$")
    private static let timeOrDate = try! NSRegularExpression(pattern: "^(?:[0-9]{1,2}:[0-9]{0,2}(?::[0-9]{0,2})?|[0-9]{4}-[0-9]{1,2}(?:-[0-9]{0,2})?)$")
}
