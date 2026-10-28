import XCTest
@testable import MonkeyCore

final class TranslationDraftTests: XCTestCase {
    func testLateResponseCannotOverwriteEditedDraft() throws {
        var draft = TranslationDraft()
        draft.append("明天下午开会")
        let old = try XCTUnwrap(draft.beginRequest())
        draft.append("，改到三点")
        XCTAssertFalse(draft.complete("Wrong old result", for: old))
        XCTAssertEqual(draft.source, "明天下午开会，改到三点")
        XCTAssertFalse(draft.canConfirm)
        let current = try XCTUnwrap(draft.beginRequest())
        XCTAssertTrue(draft.complete("Let’s meet at 3 p.m. tomorrow.", for: current))
        XCTAssertTrue(draft.canConfirm)
    }

    func testPartialStreamIsNeverConfirmableAndFailureKeepsChinese() throws {
        var draft = TranslationDraft()
        draft.append("不要取消会议")
        let request = try XCTUnwrap(draft.beginRequest())
        XCTAssertTrue(draft.receivePreview("Don't", for: request))
        XCTAssertFalse(draft.canConfirm)
        XCTAssertTrue(draft.fail("订阅额度不足", for: request))
        XCTAssertEqual(draft.source, "不要取消会议")
        XCTAssertEqual(draft.translation, "")
        XCTAssertFalse(draft.canConfirm)
    }

    func testCancelledOrResetSessionRejectsResponse() throws {
        var draft = TranslationDraft()
        draft.append("你好")
        let request = try XCTUnwrap(draft.beginRequest())
        draft.reset()
        draft.append("新输入框")
        XCTAssertFalse(draft.complete("Hello", for: request))
        XCTAssertEqual(draft.source, "新输入框")
    }

    func testBackspaceUsesGraphemesAndInvalidatesReadyTranslation() throws {
        var draft = TranslationDraft()
        draft.append("测试👨‍👩‍👧‍👦")
        let request = try XCTUnwrap(draft.beginRequest())
        draft.complete("Test", for: request)
        draft.removeLastCharacter()
        XCTAssertEqual(draft.source, "测试")
        XCTAssertFalse(draft.canConfirm)
    }
}
