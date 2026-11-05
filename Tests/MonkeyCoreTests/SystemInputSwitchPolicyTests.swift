import XCTest
@testable import MonkeyCore

final class SystemInputSwitchPolicyTests: XCTestCase {
    func testRawCommitRequiresActiveSessionASCIILayoutAndSameKnownForegroundApp() {
        XCTAssertTrue(SystemInputSwitchPolicy.shouldCommitRaw(active: true, observedMonkeySource: true, isASCIICapableKeyboardLayout: true,
                                                              activationProcessID: 123, currentProcessID: 123))
        XCTAssertFalse(SystemInputSwitchPolicy.shouldCommitRaw(active: true, observedMonkeySource: false, isASCIICapableKeyboardLayout: true,
                                                               activationProcessID: 123, currentProcessID: 123))
        XCTAssertFalse(SystemInputSwitchPolicy.shouldCommitRaw(active: false, observedMonkeySource: true, isASCIICapableKeyboardLayout: true,
                                                               activationProcessID: 123, currentProcessID: 123))
        XCTAssertFalse(SystemInputSwitchPolicy.shouldCommitRaw(active: true, observedMonkeySource: true, isASCIICapableKeyboardLayout: false,
                                                               activationProcessID: 123, currentProcessID: 123))
        XCTAssertFalse(SystemInputSwitchPolicy.shouldCommitRaw(active: true, observedMonkeySource: true, isASCIICapableKeyboardLayout: true,
                                                               activationProcessID: 123, currentProcessID: 456))
        XCTAssertFalse(SystemInputSwitchPolicy.shouldCommitRaw(active: true, observedMonkeySource: true, isASCIICapableKeyboardLayout: true,
                                                               activationProcessID: nil, currentProcessID: 123))
        XCTAssertFalse(SystemInputSwitchPolicy.shouldCommitRaw(active: true, observedMonkeySource: true, isASCIICapableKeyboardLayout: true,
                                                               activationProcessID: 123, currentProcessID: nil))
        XCTAssertFalse(SystemInputSwitchPolicy.shouldCommitRaw(active: true, observedMonkeySource: true, isASCIICapableKeyboardLayout: true,
                                                               activationProcessID: nil, currentProcessID: nil))
    }
}
