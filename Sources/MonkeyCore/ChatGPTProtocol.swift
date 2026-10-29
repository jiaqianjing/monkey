import Foundation
import CryptoKit
import Security

public enum ChatGPTError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

public struct ChatGPTModel: Codable, Identifiable, Hashable {
    public let slug: String
    public let displayName: String
    public var id: String { slug }
    public init(slug: String, displayName: String) { self.slug = slug; self.displayName = displayName }
}

public struct ChatGPTAccount: Codable, Identifiable, Hashable, Sendable {
    public let clientID: String
    public let subject: String
    public let email: String
    public var id: String { clientID }
}

struct ChatGPTCredential: Codable, Sendable {
    var account: ChatGPTAccount
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var expiresAt: Date
    var earliestRefreshAt: Date?
    var scopes: [String]
}

enum ChatGPTOAuth {
    static let issuer = "https://auth.openai.com"
    static let resource = "https://api.openai.com/v1"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"

    static func randomURLString(bytes: Int = 32) throws -> String {
        var values = [UInt8](repeating: 0, count: bytes)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes, &values) == errSecSuccess else {
            throw ChatGPTError.message("无法创建安全的登录请求。")
        }
        return Data(values).base64URL
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
    }

    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }

    static func callback(_ url: URL, state: String, existingClientID: String?) throws -> (code: String, clientID: String) {
        guard url.host == "127.0.0.1", url.path == "/auth/callback",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ChatGPTError.message("登录回调地址不正确。")
        }
        let items = components.queryItems ?? []
        // Reject ambiguous duplicate security parameters instead of picking one.
        for name in ["state", "code", "client_id", "error"] where items.filter({ $0.name == name }).count > 1 {
            throw ChatGPTError.message("登录回调包含重复参数。")
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == state else { throw ChatGPTError.message("登录状态校验失败，请重新登录。") }
        if let oauthError = value("error") {
            throw ChatGPTError.message(oauthError == "access_denied" ? "登录或订阅授权已取消。" : "ChatGPT 未完成授权，请重试。")
        }
        guard let code = value("code"), !code.isEmpty else { throw ChatGPTError.message("登录未返回授权码。") }
        let returned = value("client_id")
        if let existingClientID, let returned, returned != existingClientID {
            throw ChatGPTError.message("登录返回了其他连接，已保留原账号。")
        }
        guard let client = existingClientID ?? returned, !client.isEmpty, client != "dynamic_agent_client" else {
            throw ChatGPTError.message("ChatGPT 连接注册尚未完成，请重新登录。")
        }
        return (code, client)
    }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        var string = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        string += String(repeating: "=", count: (4 - string.count % 4) % 4)
        self.init(base64Encoded: string)
    }
}

/// State is held only until a completed terminal event; deltas alone are never success.
struct ChatGPTStreamAccumulator {
    private(set) var text = ""
    private(set) var completed = false
    private var dataLines: [String] = []
    private var eventName = ""

    mutating func consume(line: String) throws -> String? {
        if line.isEmpty { return try dispatch() }
        if line.hasPrefix(":") { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        if field == "data" { dataLines.append(value) }
        if field == "event" { eventName = value }
        return nil
    }

    mutating func finish() throws -> String {
        _ = try dispatch()
        guard completed else { throw ChatGPTError.message("翻译连接提前结束，原文已保留，请重试。") }
        let output = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { throw ChatGPTError.message("模型没有返回译文，请重试。") }
        return output
    }

    private mutating func dispatch() throws -> String? {
        defer { dataLines = []; eventName = "" }
        guard !dataLines.isEmpty else { return nil }
        let payload = dataLines.joined(separator: "\n")
        if payload == "[DONE]" { return nil }
        guard let json = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw ChatGPTError.message("翻译服务返回了无法识别的数据。")
        }
        let type = json["type"] as? String ?? eventName
        if type == "response.output_text.delta", let delta = json["delta"] as? String {
            guard !completed else { throw ChatGPTError.message("翻译数据顺序异常。") }
            text += delta
            return delta
        }
        if type == "response.completed" {
            let response = json["response"] as? [String: Any]
            if let status = response?["status"] as? String, status != "completed" {
                throw ChatGPTError.message("翻译没有完整完成。")
            }
            if text.isEmpty, let output = response?["output"] as? [[String: Any]] {
                text = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                    .filter { $0["type"] as? String == "output_text" }
                    .compactMap { $0["text"] as? String }.joined()
            }
            completed = true
        }
        if ["response.failed", "response.incomplete", "error"].contains(type) {
            let response = json["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any] ?? json["error"] as? [String: Any] ?? json
            throw ChatGPTError.message(Self.message(for: error["code"] as? String))
        }
        return nil
    }

    static func message(for code: String?) -> String {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return "ChatGPT 共享订阅额度已用完。请稍后重试或前往 ChatGPT 管理用量。"
        case "subscription_sharing_usage_unavailable": return "当前账号暂不能使用订阅额度。请检查 ChatGPT 授权与套餐。"
        case "invalid_api_key", "invalid_token", "token_expired": return "ChatGPT 登录已失效，请重新登录。"
        case "rate_limit_exceeded": return "请求过于频繁，请稍后重试。"
        default: return "翻译未完成，原文已保留，请重试。"
        }
    }
}

/// Foundation's `AsyncBytes.lines` drops empty lines, which are SSE event delimiters.
/// Decode UTF-8 only after a complete byte line so split multibyte characters survive.
struct ChatGPTSSELineDecoder {
    private var buffer = Data()
    private var previousWasCR = false

    mutating func consume(_ byte: UInt8) throws -> String? {
        if byte == 10 && previousWasCR { previousWasCR = false; return nil }
        if byte == 10 || byte == 13 {
            previousWasCR = byte == 13
            return try takeLine()
        }
        previousWasCR = false
        buffer.append(byte)
        guard buffer.count <= 1_048_576 else { throw ChatGPTError.message("翻译服务返回的数据行过长。") }
        return nil
    }

    mutating func finish() throws -> String? {
        guard !buffer.isEmpty else { return nil }
        return try takeLine()
    }

    private mutating func takeLine() throws -> String {
        defer { buffer.removeAll(keepingCapacity: true) }
        guard let line = String(data: buffer, encoding: .utf8) else {
            throw ChatGPTError.message("翻译服务返回了无效的文字编码。")
        }
        return line
    }
}

@MainActor
enum ChatGPTSSETransport {
    static func decode(
        _ bytes: URLSession.AsyncBytes,
        validate: () throws -> Void = {},
        onDelta: ((String) -> Void)? = nil
    ) async throws -> String {
        var lines = ChatGPTSSELineDecoder()
        var events = ChatGPTStreamAccumulator()
        for try await byte in bytes {
            try Task.checkCancellation()
            try validate()
            if let line = try lines.consume(byte), let delta = try events.consume(line: line) { onDelta?(delta) }
            if events.completed { break }
        }
        if let line = try lines.finish(), let delta = try events.consume(line: line) { onDelta?(delta) }
        try validate()
        return try events.finish()
    }
}
