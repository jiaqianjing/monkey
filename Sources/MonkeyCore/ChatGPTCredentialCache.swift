import Foundation

/// The cache belongs to one selected account/revision, never to a document.
/// A noninteractive failure is latched until an explicit authorization action or
/// a changed credential revision, so automatic previews cannot create a prompt loop.
@MainActor
final class ChatGPTCredentialCache {
    private var clientID: String?
    private var revision: String?
    private var credential: ChatGPTCredential?
    private var didLoad = false
    private var readTask: Task<ChatGPTCredential?, Error>?
    private var generation = UUID()
    private var failure: Error?

    var hasCredential: Bool { credential != nil }
    var requiresAuthorization: Bool { failure is KeychainAccessError }

    func synchronize(clientID: String?, revision: String?) {
        guard self.clientID != clientID || self.revision != revision else { return }
        invalidate()
        self.clientID = clientID
        self.revision = revision
    }

    func invalidate() {
        readTask?.cancel()
        readTask = nil
        credential = nil
        didLoad = false
        failure = nil
        generation = UUID()
    }

    func store(_ credential: ChatGPTCredential, clientID: String, revision: String?) {
        synchronize(clientID: clientID, revision: revision)
        invalidate()
        self.credential = credential
        didLoad = true
        failure = nil
    }

    func blockAuthorization(_ error: KeychainAccessError) {
        invalidate()
        failure = error
    }

    func load(
        clientID: String,
        revision: String?,
        authorize: Bool = false,
        reader: @escaping (Bool) async throws -> ChatGPTCredential?
    ) async throws -> ChatGPTCredential? {
        synchronize(clientID: clientID, revision: revision)
        if authorize { invalidate() }
        if didLoad { return credential }
        if let failure { throw failure }
        let currentGeneration = generation
        if let readTask {
            let loaded = try await readTask.value
            guard currentGeneration == generation else { throw CancellationError() }
            try Task.checkCancellation()
            return loaded
        }
        let task = Task { try await reader(authorize) }
        readTask = task
        do {
            let loaded = try await task.value
            guard currentGeneration == generation else { throw CancellationError() }
            try Task.checkCancellation()
            credential = loaded
            didLoad = true
            readTask = nil
            return loaded
        } catch {
            guard currentGeneration == generation else { throw CancellationError() }
            readTask = nil
            if error is KeychainAccessError { failure = error }
            throw error
        }
    }
}

/// Local elapsed times only. This never includes text, tokens, account IDs or URLs.
public struct TranslationLatency: Equatable, Sendable {
    public let firstTokenMilliseconds: Double?
    public let completionMilliseconds: Double
}
