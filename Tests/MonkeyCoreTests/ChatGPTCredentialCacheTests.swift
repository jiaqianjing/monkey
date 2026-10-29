import Security
import XCTest
@testable import MonkeyCore

final class ChatGPTCredentialCacheTests: XCTestCase {
    @MainActor
    func testRepeatedPreviewUsesOneNoninteractiveReadUntilRevisionChanges() async throws {
        let cache = ChatGPTCredentialCache()
        var reads = 0
        let credential = fixture()
        let reader: (Bool) async throws -> ChatGPTCredential? = { allowUI in
            XCTAssertFalse(allowUI)
            reads += 1
            return credential
        }
        for _ in 0..<8 {
            cache.synchronize(clientID: "first", revision: "v1")
            let result = try await cache.load(clientID: "first", revision: "v1", reader: reader)
            XCTAssertEqual(result?.accessToken, "fixture-only")
        }
        XCTAssertEqual(reads, 1)
        _ = try await cache.load(clientID: "first", revision: "v2", reader: reader)
        XCTAssertEqual(reads, 2, "A token rotated in another process invalidates the cached credential")
    }

    @MainActor
    func testMissingCredentialIsRememberedUntilExplicitRetry() async throws {
        let cache = ChatGPTCredentialCache()
        var reads = 0
        for _ in 0..<4 {
            let missing = try await cache.load(clientID: "first", revision: "v1") { _ in
                reads += 1
                return nil
            }
            XCTAssertNil(missing)
        }
        XCTAssertEqual(reads, 1)
        _ = try await cache.load(clientID: "first", revision: "v1", authorize: true) { allowUI in
            XCTAssertTrue(allowUI)
            reads += 1
            return self.fixture()
        }
        XCTAssertEqual(reads, 2)
        XCTAssertTrue(cache.hasCredential)
    }

    @MainActor
    func testDeniedAccessLatchesUntilExplicitAuthorization() async throws {
        let cache = ChatGPTCredentialCache()
        var reads = 0
        for _ in 0..<4 {
            do {
                _ = try await cache.load(clientID: "first", revision: "v1") { allowUI in
                    XCTAssertFalse(allowUI)
                    reads += 1
                    throw KeychainAccessError(status: errSecInteractionNotAllowed)
                }
                XCTFail("Unapproved access must fail")
            } catch { XCTAssertTrue(error is KeychainAccessError) }
        }
        XCTAssertEqual(reads, 1, "Typing again must not re-enter Keychain after a denial")
        XCTAssertTrue(cache.requiresAuthorization)
        let result = try await cache.load(clientID: "first", revision: "v1", authorize: true) { allowUI in
            XCTAssertTrue(allowUI)
            reads += 1
            return self.fixture()
        }
        XCTAssertNotNil(result)
        XCTAssertFalse(cache.requiresAuthorization)
        XCTAssertEqual(reads, 2)
    }

    @MainActor
    func testAccountSwitchAndSignoutForgetCredentialsAndDeniedState() async throws {
        let cache = ChatGPTCredentialCache()
        cache.store(fixture(), clientID: "first", revision: "v1")
        cache.synchronize(clientID: "second", revision: "v1")
        XCTAssertFalse(cache.hasCredential)
        cache.blockAuthorization(KeychainAccessError(status: errSecUserCanceled))
        XCTAssertTrue(cache.requiresAuthorization)
        cache.synchronize(clientID: nil, revision: nil)
        XCTAssertFalse(cache.requiresAuthorization)
        XCTAssertFalse(cache.hasCredential)
    }

    @MainActor
    func testCancelledOldAccountReadCannotPopulateNewAccount() async throws {
        let cache = ChatGPTCredentialCache()
        let gate = PendingCredentialRead()
        let task = Task {
            try await cache.load(clientID: "first", revision: "v1") { _ in await gate.read() }
        }
        await gate.waitUntilStarted()
        cache.synchronize(clientID: "second", revision: "v1")
        gate.complete(fixture())
        do { _ = try await task.value; XCTFail("Old account result must be rejected") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(cache.hasCredential)
    }

    @MainActor
    func testConcurrentRequestsShareReadAndRejectItAfterAccountSwitch() async throws {
        let cache = ChatGPTCredentialCache()
        let gate = PendingCredentialRead()
        let first = Task { try await cache.load(clientID: "first", revision: "v1") { _ in await gate.read() } }
        await gate.waitUntilStarted()
        let secondStarted = expectation(description: "second caller waiting")
        let second = Task {
            secondStarted.fulfill()
            return try await cache.load(clientID: "first", revision: "v1") { _ in
                XCTFail("Concurrent preview must reuse the existing read")
                return self.fixture()
            }
        }
        await fulfillment(of: [secondStarted], timeout: 1)
        cache.synchronize(clientID: "second", revision: "v2")
        gate.complete(fixture())
        for task in [first, second] {
            do { _ = try await task.value; XCTFail("Both pending results must be stale") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
    }

    @MainActor
    func testNewCredentialCannotBeOverwrittenByPendingOldRead() async throws {
        let cache = ChatGPTCredentialCache()
        let gate = PendingCredentialRead()
        let old = Task { try await cache.load(clientID: "first", revision: "v1") { _ in await gate.read() } }
        await gate.waitUntilStarted()
        var renewed = fixture()
        renewed.accessToken = "new-fixture-only"
        cache.store(renewed, clientID: "first", revision: "v2")
        gate.complete(fixture())
        do { _ = try await old.value; XCTFail("Old read must not overwrite renewed credential") }
        catch { XCTAssertTrue(error is CancellationError) }
        let result = try await cache.load(clientID: "first", revision: "v2") { _ in
            XCTFail("Renewed credential is already in memory")
            return nil
        }
        XCTAssertEqual(result?.accessToken, "new-fixture-only")
    }

    private func fixture() -> ChatGPTCredential {
        ChatGPTCredential(account: ChatGPTAccount(clientID: "first", subject: "fixture", email: "test@example.invalid"),
            accessToken: "fixture-only", refreshToken: "fixture-only", idToken: "fixture-only",
            expiresAt: Date().addingTimeInterval(3600), earliestRefreshAt: nil,
            scopes: ["resource.invoke", "chatgpt.tokens.use.direct"])
    }
}

@MainActor
private final class PendingCredentialRead {
    private var result: CheckedContinuation<ChatGPTCredential?, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    func read() async -> ChatGPTCredential? {
        await withCheckedContinuation { continuation in
            result = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }
    func waitUntilStarted() async {
        if result != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func complete(_ credential: ChatGPTCredential) {
        result?.resume(returning: credential)
        result = nil
    }
}
