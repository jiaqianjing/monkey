import Foundation
import Security
import XCTest
@testable import MonkeyCore

final class ChatGPTProtocolTests: XCTestCase {
    func testCallbackRequiresStateAndIssuedClientID() throws {
        let good = URL(string: "http://127.0.0.1:54321/auth/callback?state=expected&code=abc&client_id=oaiapp_one")!
        let result = try ChatGPTOAuth.callback(good, state: "expected", existingClientID: nil)
        XCTAssertEqual(result.code, "abc")
        XCTAssertEqual(result.clientID, "oaiapp_one")
        XCTAssertThrowsError(try ChatGPTOAuth.callback(good, state: "other", existingClientID: nil))
        XCTAssertThrowsError(try ChatGPTOAuth.callback(good, state: "expected", existingClientID: "oaiapp_other"))
        let missingID = URL(string: "http://127.0.0.1:54321/auth/callback?state=expected&code=abc")!
        XCTAssertThrowsError(try ChatGPTOAuth.callback(missingID, state: "expected", existingClientID: nil))
        XCTAssertEqual(try ChatGPTOAuth.callback(missingID, state: "expected", existingClientID: "oaiapp_one").clientID, "oaiapp_one")
    }

    func testDuplicateAndDeniedCallbacksAreRejected() {
        for query in ["state=s&state=s&code=c&client_id=x", "state=s&error=access_denied", "state=s&code=c&client_id=dynamic_agent_client"] {
            let url = URL(string: "http://127.0.0.1:54321/auth/callback?" + query)!
            XCTAssertThrowsError(try ChatGPTOAuth.callback(url, state: "s", existingClientID: nil))
        }
    }

    func testPKCEUsesRFC7636Vector() {
        XCTAssertEqual(ChatGPTOAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testSSERequiresCompletedAfterDeltas() throws {
        var parser = ChatGPTStreamAccumulator()
        try feed("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Hello\"}\n\n", to: &parser)
        XCTAssertEqual(parser.text, "Hello")
        XCTAssertThrowsError(try parser.finish())
        try feed("data: [DONE]\n\n", to: &parser)
        XCTAssertThrowsError(try parser.finish())
        try feed("event: response.completed\ndata: {\"response\":{\"status\":\"completed\"}}\n\n", to: &parser)
        XCTAssertEqual(try parser.finish(), "Hello")
    }

    func testSSELateQuotaFailureDoesNotBecomeSuccess() throws {
        var parser = ChatGPTStreamAccumulator()
        try feed("data: {\"type\":\"response.output_text.delta\",\"delta\":\"partial\"}\n\n", to: &parser)
        XCTAssertThrowsError(try feed("data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}}\n\n", to: &parser)) { error in
            XCTAssertTrue(error.localizedDescription.contains("额度"))
        }
        XCTAssertFalse(parser.completed)
    }

    func testSSEMultilineAndFinalTextFallback() throws {
        var parser = ChatGPTStreamAccumulator()
        try feed(": heartbeat\ndata: {\"type\":\"response.completed\",\ndata: \"response\":{\"status\":\"completed\",\"output\":[{\"content\":[{\"type\":\"output_text\",\"text\":\"Tomorrow works.\"}]}]}}\n\n", to: &parser)
        XCTAssertEqual(try parser.finish(), "Tomorrow works.")
    }

    func testValidSignedIdentityAndTamperedSignature() throws {
        let fixture = try signedFixture()
        let identity = try ChatGPTIDTokenVerifier.verify(fixture.token, clientID: "oaiapp_test", nonce: "nonce", jwks: fixture.jwks)
        XCTAssertEqual(identity.subject, "account_test")
        XCTAssertEqual(identity.email, "test@example.invalid")
        let parts = fixture.token.components(separatedBy: ".")
        var signature = Data(base64URL: parts[2])!
        signature[0] ^= 1
        let tampered = "\(parts[0]).\(parts[1]).\(signature.base64URL)"
        XCTAssertThrowsError(try ChatGPTIDTokenVerifier.verify(tampered, clientID: "oaiapp_test", nonce: "nonce", jwks: fixture.jwks))
        XCTAssertThrowsError(try ChatGPTIDTokenVerifier.verify(fixture.token, clientID: "other", nonce: "nonce", jwks: fixture.jwks))
        XCTAssertThrowsError(try ChatGPTIDTokenVerifier.verify(fixture.token, clientID: "oaiapp_test", nonce: "wrong", jwks: fixture.jwks))
    }

    func testIdentityRejectsExpiredWrongIssuerAndMultipleAudienceWithoutAZP() throws {
        let now = Date()
        let base: [String: Any] = ["iss": ChatGPTOAuth.issuer, "aud": "client", "sub": "subject", "exp": now.timeIntervalSince1970 + 60, "nonce": "nonce"]
        for change in [["exp": now.timeIntervalSince1970 - 1], ["iss": "https://example.invalid"], ["aud": ["client", "other"]], ["nbf": now.timeIntervalSince1970 + 120]] as [[String: Any]] {
            let claims = base.merging(change, uniquingKeysWith: { _, value in value })
            XCTAssertThrowsError(try ChatGPTIDTokenVerifier.validateClaims(claims, clientID: "client", nonce: "nonce", now: now))
        }
    }

    func testRefreshLockSerializesIndependentInstances() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try ChatGPTRefreshLock(clientID: "same-account", directory: directory)
        let second = try ChatGPTRefreshLock(clientID: "same-account", directory: directory)
        XCTAssertTrue(try first.tryAcquire())
        XCTAssertFalse(try second.tryAcquire())
        first.release()
        XCTAssertTrue(try second.tryAcquire())
        second.release()
    }

    private func feed(_ string: String, to parser: inout ChatGPTStreamAccumulator) throws {
        for line in string.components(separatedBy: "\n") { _ = try parser.consume(line: line) }
    }

    private func signedFixture() throws -> (token: String, jwks: Data) {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048]
        let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, nil)!
        let publicKey = SecKeyCopyPublicKey(privateKey)!
        let der = SecKeyCopyExternalRepresentation(publicKey, nil)! as Data
        var bytes = [UInt8](der)
        var offset = 0
        func readLength() -> Int {
            let byte = bytes[offset]; offset += 1
            if byte < 128 { return Int(byte) }
            var result = 0
            for _ in 0..<Int(byte & 0x7f) { result = result * 256 + Int(bytes[offset]); offset += 1 }
            return result
        }
        XCTAssertEqual(bytes[offset], 0x30); offset += 1; _ = readLength()
        XCTAssertEqual(bytes[offset], 0x02); offset += 1; let nLength = readLength()
        let n = Data(bytes[offset..<(offset + nLength)].drop(while: { $0 == 0 })); offset += nLength
        XCTAssertEqual(bytes[offset], 0x02); offset += 1; let eLength = readLength()
        let e = Data(bytes[offset..<(offset + eLength)])
        let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": "test"]).base64URL
        let claims: [String: Any] = ["iss": ChatGPTOAuth.issuer, "aud": "oaiapp_test", "sub": "account_test",
            "email": "test@example.invalid", "exp": Date().timeIntervalSince1970 + 60, "nonce": "nonce"]
        let payload = try JSONSerialization.data(withJSONObject: claims).base64URL
        let message = Data("\(header).\(payload)".utf8)
        let signature = SecKeyCreateSignature(privateKey, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, nil)! as Data
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kty": "RSA", "kid": "test", "alg": "RS256", "use": "sig", "n": n.base64URL, "e": e.base64URL]]])
        bytes.removeAll()
        return ("\(header).\(payload).\(signature.base64URL)", jwks)
    }
}
