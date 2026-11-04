import Foundation
import XCTest
@testable import MonkeyCore

final class ChatGPTConnectionRemovalTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MonkeyCoreTests.connection-removal.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    func testRemovingCurrentConnectionClearsItsRegistrationWithoutSelectingAnotherAccount() async throws {
        let current = account("current")
        let other = account("other")
        try save([current, other])
        defaults.set(current.clientID, forKey: "ChatGPT.activeClientID")
        defaults.set("model-current", forKey: "ChatGPT.selectedModel")
        defaults.set("unfinished-registration", forKey: "ChatGPT.pendingClientID")
        defaults.set([current.clientID, other.clientID], forKey: "ChatGPT.disabledClients")
        defaults.set("revision-current", forKey: "ChatGPT.credentialRevision.current")
        defaults.set("revision-other", forKey: "ChatGPT.credentialRevision.other")
        defaults.set("urn:uuid:stable-host", forKey: "ChatGPT.hostID")
        defaults.set("business", forKey: "translationTone")
        defaults.set(true, forKey: "pinyin.fixturePreference")
        var credentialDeletions = 0

        let removedCurrent = try await ChatGPTConnectionRemoval.remove(current.clientID, from: defaults, domain: suiteName) {
            credentialDeletions += 1
            XCTAssertEqual(try self.savedAccounts(), [current, other], "Keep the registration until its credential deletion succeeds")
        }

        XCTAssertTrue(removedCurrent)
        XCTAssertEqual(credentialDeletions, 1)
        XCTAssertEqual(try savedAccounts(), [other])
        XCTAssertNil(defaults.string(forKey: "ChatGPT.activeClientID"), "Deleting the active connection must not silently switch billing accounts")
        XCTAssertNil(defaults.string(forKey: "ChatGPT.selectedModel"))
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.pendingClientID"), "unfinished-registration", "Preserve another registration in progress")
        XCTAssertNil(defaults.string(forKey: "ChatGPT.credentialRevision.current"))
        XCTAssertEqual(defaults.stringArray(forKey: "ChatGPT.disabledClients"), [other.clientID])
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.credentialRevision.other"), "revision-other")
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.hostID"), "urn:uuid:stable-host")
        XCTAssertEqual(defaults.string(forKey: "translationTone"), "business")
        XCTAssertTrue(defaults.bool(forKey: "pinyin.fixturePreference"))
    }

    @MainActor
    func testRemovingAnotherConnectionPreservesActiveAccountModelAndUnrelatedPendingLogin() async throws {
        let current = account("current")
        let other = account("other")
        try save([current, other])
        defaults.set(current.clientID, forKey: "ChatGPT.activeClientID")
        defaults.set("model-current", forKey: "ChatGPT.selectedModel")
        defaults.set("unrelated-pending", forKey: "ChatGPT.pendingClientID")
        defaults.set([other.clientID], forKey: "ChatGPT.disabledClients")
        defaults.set("revision-current", forKey: "ChatGPT.credentialRevision.current")
        defaults.set("revision-other", forKey: "ChatGPT.credentialRevision.other")
        var credentialDeletions = 0

        let removedCurrent = try await ChatGPTConnectionRemoval.remove(other.clientID, from: defaults, domain: suiteName) {
            credentialDeletions += 1
        }

        XCTAssertFalse(removedCurrent)
        XCTAssertEqual(credentialDeletions, 1)
        XCTAssertEqual(try savedAccounts(), [current])
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.activeClientID"), current.clientID)
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.selectedModel"), "model-current")
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.pendingClientID"), "unrelated-pending")
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.credentialRevision.current"), "revision-current")
        XCTAssertNil(defaults.string(forKey: "ChatGPT.credentialRevision.other"))
        XCTAssertFalse((defaults.stringArray(forKey: "ChatGPT.disabledClients") ?? []).contains(other.clientID))
    }

    @MainActor
    func testCredentialDeletionFailureLeavesConnectionMetadataAvailableForRetry() async throws {
        let current = account("current")
        try save([current])
        defaults.set(current.clientID, forKey: "ChatGPT.activeClientID")
        defaults.set("model-current", forKey: "ChatGPT.selectedModel")
        defaults.set("pending", forKey: "ChatGPT.pendingClientID")
        defaults.set([current.clientID], forKey: "ChatGPT.disabledClients")
        defaults.set("revision-current", forKey: "ChatGPT.credentialRevision.current")
        defaults.set("urn:uuid:stable-host", forKey: "ChatGPT.hostID")
        let before = NSDictionary(dictionary: defaults.persistentDomain(forName: suiteName) ?? [:])

        do {
            _ = try await ChatGPTConnectionRemoval.remove(current.clientID, from: defaults, domain: suiteName) {
                throw RemovalFailure.credentialDeletionDenied
            }
            XCTFail("The caller must see a failed credential deletion")
        } catch {
            XCTAssertTrue(error is RemovalFailure)
        }

        XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: suiteName) ?? [:]), before)
    }

    @MainActor
    func testRemovingLastSignedOutConnectionLeavesNoRegistrationToReuseOnNextLogin() async throws {
        let old = account("old")
        try save([old])
        defaults.set("unfinished-registration", forKey: "ChatGPT.pendingClientID")
        defaults.set([old.clientID], forKey: "ChatGPT.disabledClients")
        defaults.set("urn:uuid:stable-host", forKey: "ChatGPT.hostID")

        let removedCurrent = try await ChatGPTConnectionRemoval.remove(old.clientID, from: defaults, domain: suiteName) {}

        XCTAssertFalse(removedCurrent)
        XCTAssertTrue(try savedAccounts().isEmpty)
        XCTAssertNil(defaults.string(forKey: "ChatGPT.activeClientID"))
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.pendingClientID"), "unfinished-registration")
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.hostID"), "urn:uuid:stable-host", "Removing a registration must retain this Mac's stable identity")
    }

    @MainActor
    func testRemovingConnectionAlsoClearsItsMatchingPendingRegistration() async throws {
        let current = account("current")
        let other = account("other")
        try save([current, other])
        defaults.set(current.clientID, forKey: "ChatGPT.activeClientID")
        defaults.set(other.clientID, forKey: "ChatGPT.pendingClientID")

        _ = try await ChatGPTConnectionRemoval.remove(other.clientID, from: defaults, domain: suiteName) {}

        XCTAssertEqual(try savedAccounts(), [current])
        XCTAssertEqual(defaults.string(forKey: "ChatGPT.activeClientID"), current.clientID)
        XCTAssertNil(defaults.string(forKey: "ChatGPT.pendingClientID"))
    }

    @MainActor
    func testUnknownConnectionDoesNotDeleteCredentialsOrChangeAnySavedState() async throws {
        let current = account("current")
        try save([current])
        defaults.set(current.clientID, forKey: "ChatGPT.activeClientID")
        defaults.set("model-current", forKey: "ChatGPT.selectedModel")
        let before = NSDictionary(dictionary: defaults.persistentDomain(forName: suiteName) ?? [:])
        var credentialDeletions = 0

        let removedCurrent = try await ChatGPTConnectionRemoval.remove("unknown", from: defaults, domain: suiteName) {
            credentialDeletions += 1
        }

        XCTAssertFalse(removedCurrent)
        XCTAssertEqual(credentialDeletions, 0)
        XCTAssertEqual(NSDictionary(dictionary: defaults.persistentDomain(forName: suiteName) ?? [:]), before)
    }

    private func account(_ clientID: String) -> ChatGPTAccount {
        ChatGPTAccount(clientID: clientID, subject: "subject-\(clientID)", email: "\(clientID)@example.invalid")
    }

    private func save(_ accounts: [ChatGPTAccount]) throws {
        defaults.set(try JSONEncoder().encode(accounts), forKey: "ChatGPT.accounts")
    }

    private func savedAccounts() throws -> [ChatGPTAccount] {
        try JSONDecoder().decode([ChatGPTAccount].self, from: defaults.data(forKey: "ChatGPT.accounts") ?? Data("[]".utf8))
    }

    private enum RemovalFailure: Error {
        case credentialDeletionDenied
    }
}
