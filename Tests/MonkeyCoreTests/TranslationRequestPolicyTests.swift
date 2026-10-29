import XCTest
@testable import MonkeyCore

final class TranslationRequestPolicyTests: XCTestCase {
    func testSpeedPolicyOnlyAppliesToDocumentedExactModel() {
        XCTAssertEqual(TranslationRequestPolicy.reasoningEffort(model: "gpt-6.1-terra", preferSpeed: true), "none")
        XCTAssertNil(TranslationRequestPolicy.reasoningEffort(model: "gpt-6.1-terra", preferSpeed: false))
        for other in ["gpt-6-astra", "gpt-6.1-sol", "gpt-6.1-terra-unverified", "unknown", ""] {
            XCTAssertNil(TranslationRequestPolicy.reasoningEffort(model: other, preferSpeed: true))
        }
    }
}
