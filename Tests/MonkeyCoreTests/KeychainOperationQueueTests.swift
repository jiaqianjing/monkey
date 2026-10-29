import Security
import XCTest
@testable import MonkeyCore

final class KeychainOperationQueueTests: XCTestCase {
    func testNoninteractiveSuccessAndFailureRestoreOriginalPolicy() async throws {
        for initial in [true, false] {
            let policy = FakeKeychainInteractionPolicy(initial: initial)
            let queue = policy.makeQueue()
            let result = try await queue.perform(allowAuthenticationUI: false) {
                XCTAssertFalse(policy.allowed)
                return "nonsecret fixture"
            }
            XCTAssertEqual(result, "nonsecret fixture")
            XCTAssertEqual(policy.allowed, initial)
            do {
                _ = try await queue.perform(allowAuthenticationUI: false) { () throws -> String in
                    XCTAssertFalse(policy.allowed)
                    throw KeychainAccessError(status: errSecInteractionNotAllowed)
                }
                XCTFail("Denied operation must fail")
            } catch { XCTAssertTrue(error is KeychainAccessError) }
            XCTAssertEqual(policy.allowed, initial, "Even denied reads restore the original UI policy")
            XCTAssertEqual(policy.writes, [false, initial, false, initial])
        }
    }

    func testExplicitAuthorizationWaitsForNoninteractiveReadAndSeesRestoredPolicy() async throws {
        let policy = FakeKeychainInteractionPolicy(initial: true)
        let queue = policy.makeQueue()
        let entered = expectation(description: "noninteractive operation entered")
        let release = DispatchSemaphore(value: 0)
        let first = Task {
            try await queue.perform(allowAuthenticationUI: false) {
                XCTAssertFalse(policy.allowed)
                entered.fulfill()
                XCTAssertEqual(release.wait(timeout: .now() + 2), .success)
                return 1
            }
        }
        await fulfillment(of: [entered], timeout: 1)
        let second = Task {
            try await queue.perform(allowAuthenticationUI: true) {
                XCTAssertTrue(policy.allowed, "Explicit authorization cannot race the temporary no-UI scope")
                return 2
            }
        }
        release.signal()
        let firstResult = try await first.value
        let secondResult = try await second.value
        XCTAssertEqual(firstResult, 1)
        XCTAssertEqual(secondResult, 2)
        XCTAssertEqual(policy.writes, [false, true])
    }

    func testPolicyReadOrRestrictionFailureNeverReadsCredential() async throws {
        for failGet in [true, false] {
            let queue = KeychainOperationQueue(getInteractionAllowed: {
                if failGet { throw KeychainAccessError(status: errSecNotAvailable) }
                return true
            }, setInteractionAllowed: { _ in throw KeychainAccessError(status: errSecNotAvailable) })
            do {
                _ = try await queue.perform(allowAuthenticationUI: false) { () -> Int in
                    XCTFail("Fail closed if UI cannot be restricted")
                    return 0
                }
                XCTFail("Policy error must be surfaced")
            } catch { XCTAssertTrue(error is KeychainAccessError) }
        }
    }

    func testExplicitAuthorizationNeverForcesPolicyToTrue() async throws {
        let policy = FakeKeychainInteractionPolicy(initial: false)
        let result = try await policy.makeQueue().perform(allowAuthenticationUI: true) {
            XCTAssertFalse(policy.allowed)
            return 1
        }
        XCTAssertEqual(result, 1)
        XCTAssertTrue(policy.writes.isEmpty)
    }
}

private final class FakeKeychainInteractionPolicy: @unchecked Sendable {
    // This state is accessed only through one serial operation queue. The test
    // reads it after awaited operations complete; no real Keychain is used.
    var allowed: Bool
    var writes: [Bool] = []
    init(initial: Bool) { allowed = initial }
    func makeQueue() -> KeychainOperationQueue {
        KeychainOperationQueue(getInteractionAllowed: { self.allowed }, setInteractionAllowed: {
            self.allowed = $0
            self.writes.append($0)
        })
    }
}
