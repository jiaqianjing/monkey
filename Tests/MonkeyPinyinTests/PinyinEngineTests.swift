import Foundation
import MonkeyPinyin
import XCTest

final class PinyinEngineTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testRealDictionaryFullPinyinAbbreviationSentenceAndPunctuation() async throws {
        let shared = root.appendingPathComponent("Resources/Rime")
        let library = root.appendingPathComponent("Vendor/Rime/lib/librime.1.dylib")
        let user = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyPinyin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: user) }
        try await MainActor.run {
            let engine = try PinyinEngine(sharedDataURL: shared, userDataURL: user, libraryURL: library)
            let session = try engine.makeSession()
            defer { session.close() }

            for (pinyin, expected) in [("nihao", "你好"), ("zhongguo", "中国"), ("nh", "您好") ] {
                feed(pinyin, to: session)
                XCTAssertTrue(session.snapshot().candidates.contains(expected), "\(pinyin): \(session.snapshot())")
                session.clear()
            }

            feed("wojintianxianghebeikafei", to: session)
            let sentence = session.snapshot()
            XCTAssertFalse(sentence.candidates.isEmpty)
            XCTAssertTrue(sentence.candidates[0].contains("咖啡"), "\(sentence)")
            XCTAssertTrue(session.selectCandidate(0))
            let text = session.takeCommit()
            XCTAssertTrue(text?.contains("咖啡") == true, "\(String(describing: text))")
            XCTAssertTrue(session.snapshot().preedit.isEmpty)

            XCTAssertTrue(session.process(key: Int32(Character(",").asciiValue!)))
            XCTAssertEqual(session.takeCommit(), "，")
            XCTAssertTrue(session.process(key: Int32(Character(".").asciiValue!)))
            XCTAssertEqual(session.takeCommit(), "。")

            feed("nihao", to: session)
            XCTAssertTrue(session.commitComposition())
            XCTAssertEqual(session.takeCommit(), "你好")
        }
    }

    func testLearnedWordsSurviveEngineRestart() async throws {
        let shared = root.appendingPathComponent("Resources/Rime")
        let library = root.appendingPathComponent("Vendor/Rime/lib/librime.1.dylib")
        let user = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyLearning-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: user) }
        let learned = try await MainActor.run {
            try learnPhrase(shared: shared, user: user, library: library)
        }
        let files = FileManager.default.enumerator(at: user, includingPropertiesForKeys: nil)?
            .allObjects.compactMap { $0 as? URL } ?? []
        XCTAssertTrue(files.contains { $0.path.contains("monkey_pinyin.userdb") }, "Rime did not persist a user dictionary")
        try await MainActor.run {
            let engine = try PinyinEngine(sharedDataURL: shared, userDataURL: user, libraryURL: library)
            let session = try engine.makeSession()
            defer { session.close() }
            feed("nihao", to: session)
            XCTAssertEqual(session.snapshot().candidates.first, learned)
        }
    }
}

@MainActor
private func feed(_ text: String, to session: PinyinSession) {
    for scalar in text.unicodeScalars {
        XCTAssertTrue(session.process(key: Int32(scalar.value)), "Key \(scalar) was not handled")
    }
}

@MainActor
private func learnPhrase(shared: URL, user: URL, library: URL) throws -> String {
    let engine = try PinyinEngine(sharedDataURL: shared, userDataURL: user, libraryURL: library)
    let session = try engine.makeSession()
    defer { session.close() }
    feed("nihao", to: session)
    let initial = session.snapshot().candidates
    XCTAssertGreaterThan(initial.count, 1)
    let expected = initial[1]
    XCTAssertNotEqual(expected, initial[0])
    // A deliberate non-default choice must be learned, rather than merely
    // checking that the same static dictionary entry exists after reopening.
    for _ in 0..<8 {
        let index = try XCTUnwrap(session.snapshot().candidates.firstIndex(of: expected))
        XCTAssertTrue(session.selectCandidate(index))
        XCTAssertEqual(session.takeCommit(), expected)
        feed("nihao", to: session)
    }
    session.clear()
    return expected
}
