import CRimeBridge
import Foundation

public enum PinyinEngineError: LocalizedError {
    case libraryMissing
    case initializationFailed(String)
    case sessionFailed

    public var errorDescription: String? {
        switch self {
        case .libraryMissing: return "找不到中文输入引擎，请运行 scripts/bootstrap-rime.sh 后重新打包。"
        case .initializationFailed(let message): return "中文输入引擎启动失败：\(message)"
        case .sessionFailed: return "无法载入拼音词库，请检查 Rime 资源及用户目录。"
        }
    }
}

public struct PinyinSnapshot: Equatable, Sendable {
    public var preedit: String
    public var rawInput: String
    public var candidates: [String]
    public var comments: [String]
    public var caretUTF16: Int
    public var rawCaret: Int
    public var highlightedIndex: Int
    public var page: Int
    public var isLastPage: Bool

    public init(preedit: String = "", candidates: [String] = [], highlightedIndex: Int = 0,
                page: Int = 0, isLastPage: Bool = true, rawInput: String = "", comments: [String] = [], caretUTF16: Int? = nil, rawCaret: Int? = nil) {
        self.preedit = preedit
        self.rawInput = rawInput
        self.candidates = candidates
        self.comments = comments
        self.caretUTF16 = caretUTF16 ?? preedit.utf16.count
        self.rawCaret = rawCaret ?? rawInput.utf8.count
        self.highlightedIndex = highlightedIndex
        self.page = page
        self.isLastPage = isLastPage
    }
}

/// librime is process-global; all accesses stay on the main actor. Initialize
/// the engine before accepting keystrokes, because first-run deployment builds
/// the word dictionary. Each client then uses its own lightweight session.
@MainActor
public final class PinyinEngine {
    public let sharedDataURL: URL
    public let userDataURL: URL

    public init(sharedDataURL: URL, userDataURL: URL, libraryURL: URL? = nil) throws {
        self.sharedDataURL = sharedDataURL
        self.userDataURL = userDataURL
        try FileManager.default.createDirectory(at: userDataURL, withIntermediateDirectories: true)
        let library = try libraryURL ?? Self.findLibrary()
        var error = [CChar](repeating: 0, count: 2048)
        let success = monkey_rime_acquire(library.path, sharedDataURL.path, userDataURL.path, &error, error.count)
        guard success != 0 else {
            throw PinyinEngineError.initializationFailed(String(cString: error))
        }
    }

    deinit { monkey_rime_release() }

    public func makeSession() throws -> PinyinSession {
        let identifier = monkey_rime_create_session()
        guard identifier != 0 else { throw PinyinEngineError.sessionFailed }
        return PinyinSession(engine: self, identifier: identifier)
    }

    private static func findLibrary() throws -> URL {
        let candidates: [URL] = [
            Bundle.main.privateFrameworksURL?.appendingPathComponent("librime.1.dylib"),
            Bundle.main.resourceURL?.appendingPathComponent("lib/librime.1.dylib"),
            ProcessInfo.processInfo.environment["MONKEY_RIME_LIBRARY"].map { URL(fileURLWithPath: $0) },
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Vendor/Rime/lib/librime.1.dylib"),
            URL(fileURLWithPath: "/opt/homebrew/opt/librime/lib/librime.1.dylib"),
            URL(fileURLWithPath: "/usr/local/opt/librime/lib/librime.1.dylib")
        ].compactMap { $0 }
        guard let result = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw PinyinEngineError.libraryMissing
        }
        return result
    }
}

@MainActor
public final class PinyinSession {
    // Retaining the engine guarantees that Rime outlives every session.
    private let engine: PinyinEngine
    private var identifier: UInt

    fileprivate init(engine: PinyinEngine, identifier: UInt) {
        self.engine = engine
        self.identifier = identifier
    }

    deinit { monkey_rime_destroy_session(identifier) }

    @discardableResult
    public func process(key: Int32, modifiers: Int32 = 0) -> Bool {
        monkey_rime_process(identifier, key, modifiers) != 0
    }

    public func snapshot() -> PinyinSnapshot {
        guard let raw = monkey_rime_snapshot(identifier) else { return PinyinSnapshot() }
        defer { monkey_rime_free_snapshot(raw) }
        let value = raw.pointee
        let candidates = (0..<Int(value.candidate_count)).compactMap { index in
            value.candidates?[index].map { String(cString: $0) }
        }
        let comments = (0..<Int(value.candidate_count)).map { index in
            value.comments?[index].map { String(cString: $0) } ?? ""
        }
        let preedit = value.preedit.map { String(cString: $0) } ?? ""
        let utf8Prefix = preedit.utf8.prefix(max(0, Int(value.cursor_pos)))
        return PinyinSnapshot(preedit: preedit,
                              candidates: candidates,
                              highlightedIndex: Int(value.highlighted_index),
                              page: Int(value.page), isLastPage: value.is_last_page != 0,
                              rawInput: value.raw_input.map { String(cString: $0) } ?? "",
                              comments: comments, caretUTF16: String(decoding: utf8Prefix, as: UTF8.self).utf16.count,
                              rawCaret: Int(value.raw_cursor_pos))
    }

    public func takeCommit() -> String? {
        guard let text = monkey_rime_take_commit(identifier) else { return nil }
        defer { monkey_rime_free_string(text) }
        return String(cString: text)
    }

    public func clear() { monkey_rime_clear(identifier) }

    /// Confirm the complete composition, including any remaining segments.
    @discardableResult
    public func commitComposition() -> Bool {
        monkey_rime_commit_composition(identifier) != 0
    }

    @discardableResult
    public func selectCandidate(_ index: Int) -> Bool {
        guard index >= 0 && index <= Int(Int32.max) else { return false }
        return monkey_rime_select(identifier, Int32(index)) != 0
    }

    /// Remove this candidate's learned user entry without modifying shared dictionaries.
    @discardableResult
    public func forgetCandidate(_ index: Int) -> Bool {
        guard index >= 0 && index <= Int(Int32.max) else { return false }
        return monkey_rime_forget_candidate(identifier, Int32(index)) != 0
    }

    @discardableResult
    public func changePage(backward: Bool) -> Bool { monkey_rime_change_page(identifier, backward ? 1 : 0) != 0 }

    /// Close before releasing the last engine to flush the session's learned
    /// vocabulary. A closed session is inert and close is safe to repeat.
    public func close() {
        monkey_rime_destroy_session(identifier)
        identifier = 0
    }
}
