import Foundation
import MonkeyPinyin
import XCTest

final class CompositionSessionTests: XCTestCase {
    @MainActor
    private func withSession(_ body: (CompositionSession) throws -> Void) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let user = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyComposition-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: user) }
        let engine = try PinyinEngine(sharedDataURL: root.appendingPathComponent("Resources/Rime"), userDataURL: user,
                                      libraryURL: root.appendingPathComponent("Vendor/Rime/lib/librime.1.dylib"))
        let native = try engine.makeSession()
        defer { native.close() }
        try body(CompositionSession(session: native))
    }

    func testStructuredTokensPreserveOriginalCharactersAndReturnDoesNotAddNewline() async throws {
        try await MainActor.run {
            try withSession { session in
                for token in ["https://example.com/a?q=3.14", "github.com", "ken@example.com", "first.last+tag@example.co.uk", "3.14", "v0.2.0", "Sources/MonkeyCore/file.swift", "~/Documents/test.txt", "iPhone15"] {
                    session.clear()
                    var output = type(token, into: session)
                    XCTAssertEqual(session.snapshot().rawInput, token, token)
                    XCTAssertTrue(session.process(key: 0xff0d), token)
                    output += session.takeCommit() ?? ""
                    XCTAssertEqual(output, token, token)
                    XCTAssertTrue(session.snapshot().preedit.isEmpty)
                }
            }
        }
    }

    func testEnglishSpacesAndChineseSentencePunctuation() async throws {
        try await MainActor.run {
            try withSession { session in
                var output = type("hello world", into: session)
                _ = session.process(key: 0xff0d)
                output += session.takeCommit() ?? ""
                XCTAssertEqual(output, "hello world")
                for phrase in ["macOS 13", "Python 3.12", "API v2"] {
                    session.clear()
                    var mixed = type(phrase, into: session)
                    _ = session.process(key: 0xff0d)
                    mixed += session.takeCommit() ?? ""
                    XCTAssertEqual(mixed, phrase)
                }
                session.clear()
                output = type("3.14,", into: session)
                XCTAssertEqual(output, "3.14，")
                session.clear()
                output = type("ChatGPT,", into: session)
                XCTAssertEqual(output, "ChatGPT，")
                session.clear()
                session.englishSpaceInsertsSpace = false
                XCTAssertEqual(type("chatgpt ", into: session), "ChatGPT")
            }
        }
    }

    func testPinyinDigitsStillSelectCandidatesAndEnglishDigitsStayLiteral() async throws {
        try await MainActor.run {
            try withSession { session in
                _ = type("nihao", into: session)
                XCTAssertFalse(session.isLiteral)
                let expected = try XCTUnwrap(session.snapshot().candidates.first)
                XCTAssertTrue(session.process(key: 49))
                XCTAssertEqual(session.takeCommit(), expected)
                _ = type("iPhone15", into: session)
                XCTAssertTrue(session.isLiteral)
                XCTAssertEqual(session.snapshot().rawInput, "iPhone15")
            }
        }
    }

    func testLiteralEditingAndUnknownEnglishOriginalCommit() async throws {
        try await MainActor.run {
            try withSession { session in
                _ = type("v0.2.0", into: session)
                _ = session.process(key: 0xff51)
                _ = session.process(key: 0xff08)
                XCTAssertEqual(session.snapshot().rawInput, "v0.20")
                _ = session.process(key: 46)
                XCTAssertEqual(session.snapshot().rawInput, "v0.2.0")
                XCTAssertEqual(session.snapshot().caretUTF16, 5)
                _ = session.process(key: 0xff1b)
                XCTAssertTrue(session.snapshot().preedit.isEmpty)
                var output = type("foobarbaz", into: session)
                _ = session.process(key: 0xff0d)
                output += session.takeCommit() ?? ""
                XCTAssertEqual(output, "foobarbaz")
            }
        }
    }

    func testEnglishRecognitionDoesNotReorderMiddleEditsOrStealPinyinWords() async throws {
        try await MainActor.run {
            try withSession { session in
                _ = type("githu", into: session)
                _ = session.process(key: 0xff51)
                _ = session.process(key: 0xff51)
                let beforeEdit = session.snapshot()
                var expectedEdit = beforeEdit.rawInput
                expectedEdit.insert("b", at: expectedEdit.index(expectedEdit.startIndex, offsetBy: beforeEdit.rawCaret))
                _ = session.process(key: 98)
                XCTAssertEqual(session.snapshot().rawInput, expectedEdit)
                XCTAssertNotEqual(session.snapshot().rawInput, "github")
                XCTAssertFalse(session.isLiteral)
                session.clear()
                _ = type("bing", into: session)
                XCTAssertFalse(session.isLiteral)
                XCTAssertTrue(session.snapshot().candidates.contains("并"))
                session.clear()
                _ = type("baidu", into: session)
                XCTAssertFalse(session.isLiteral)
                XCTAssertEqual(session.snapshot().candidates.first, "百度")
                session.clear()
                _ = type("mainaifen", into: session)
                XCTAssertFalse(session.isLiteral)
                XCTAssertTrue(session.snapshot().candidates.contains("买奶粉"), "\(session.snapshot())")
                session.clear()
                session.automaticEnglish = false
                _ = type("main", into: session)
                let selected = try XCTUnwrap(session.snapshot().candidates.first)
                _ = session.process(key: 49)
                XCTAssertFalse(session.isLiteral)
                XCTAssertEqual(session.takeCommit(), selected)
                session.automaticEnglish = true
                for original in ["CHONGQING", "Gongsi", "AIQING"] {
                    session.clear()
                    var output = type(original, into: session)
                    _ = session.process(key: 0xff0d)
                    output += session.takeCommit() ?? ""
                    XCTAssertEqual(output, original)
                }
            }
        }
    }

    func testActualShiftModifiersPreserveProductCapitalization() async throws {
        try await MainActor.run {
            try withSession { session in
                for original in ["ChatGPT", "iPhone", "macOS", "GitHub", "SwiftUI", "API"] {
                    session.clear()
                    var output = ""
                    for scalar in original.unicodeScalars {
                        let shift: Int32 = (65...90).contains(scalar.value) ? 1 : 0
                        if !session.process(key: Int32(scalar.value), modifiers: shift) { output += String(scalar) }
                        output += session.takeCommit() ?? ""
                    }
                    _ = session.process(key: 0xff0d)
                    output += session.takeCommit() ?? ""
                    XCTAssertEqual(output, original, original)
                }
            }
        }
    }

    func testNumbersCanFlowIntoChineseWhileUnitsRemainASCII() async throws {
        try await MainActor.run {
            try withSession { session in
                XCTAssertEqual(type("2026nian ", into: session), "2026年")
                session.clear()
                XCTAssertEqual(type("10diankaihui ", into: session), "10点开会")
                for token in ["3.5kg", "16GB", "60fps", "10ms"] {
                    session.clear()
                    var output = type(token, into: session)
                    _ = session.process(key: 0xff0d)
                    output += session.takeCommit() ?? ""
                    XCTAssertEqual(output, token)
                }
            }
        }
    }
}

@MainActor
private func type(_ text: String, into session: CompositionSession) -> String {
    var output = ""
    for scalar in text.unicodeScalars {
        let handled = session.process(key: Int32(scalar.value))
        output += session.takeCommit() ?? ""
        if !handled { output += String(scalar) }
    }
    return output
}
