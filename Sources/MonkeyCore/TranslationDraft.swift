import Foundation

/// A request can change a draft only while both its identity and source revision match.
public struct TranslationRequest: Equatable, Sendable {
    public let id: UUID
    public let revision: UInt64
    public let source: String
}

public struct TranslationDraft: Sendable {
    public enum Status: Equatable, Sendable {
        case idle, waiting, translating, ready, failed(String)
    }

    public private(set) var source = ""
    public private(set) var translation = ""
    public private(set) var revision: UInt64 = 0
    public private(set) var status: Status = .idle
    public private(set) var activeRequest: TranslationRequest?

    public init() {}
    public var canConfirm: Bool { status == .ready && !source.isEmpty && !translation.isEmpty }

    public mutating func append(_ text: String) {
        guard !text.isEmpty else { return }
        source += text
        invalidate()
    }

    public mutating func removeLastCharacter() {
        guard !source.isEmpty else { return }
        source.removeLast()
        invalidate()
    }

    public mutating func replaceSource(_ text: String) {
        source = text
        invalidate()
    }

    public mutating func invalidate() {
        revision &+= 1
        activeRequest = nil
        translation = ""
        status = source.isEmpty ? .idle : .waiting
    }

    public mutating func beginRequest() -> TranslationRequest? {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let request = TranslationRequest(id: UUID(), revision: revision, source: source)
        activeRequest = request
        translation = ""
        status = .translating
        return request
    }

    @discardableResult
    public mutating func receivePreview(_ text: String, for request: TranslationRequest) -> Bool {
        guard matches(request), status == .translating else { return false }
        translation = text
        return true
    }

    @discardableResult
    public mutating func complete(_ text: String, for request: TranslationRequest) -> Bool {
        guard matches(request), status == .translating else { return false }
        translation = text.trimmingCharacters(in: .whitespacesAndNewlines)
        status = translation.isEmpty ? .failed("未收到译文，请重试") : .ready
        activeRequest = nil
        return true
    }

    @discardableResult
    public mutating func fail(_ message: String, for request: TranslationRequest) -> Bool {
        guard matches(request) else { return false }
        activeRequest = nil
        translation = ""
        status = .failed(message)
        return true
    }

    public mutating func cancel() {
        invalidate()
        status = .idle
    }

    public mutating func reset() {
        source = ""
        invalidate()
    }

    private func matches(_ request: TranslationRequest) -> Bool {
        activeRequest == request && request.revision == revision && request.source == source
    }
}
