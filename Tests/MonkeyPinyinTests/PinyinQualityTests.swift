import Foundation
import MonkeyPinyin
import XCTest

final class PinyinQualityTests: XCTestCase {
    private struct Corpus: Decodable { let cases: [Item] }
    private struct Item: Decodable { let input: String; let expected: [String]; let category: String }
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testDailyShortcutsAndFrozenTypoChallengeKeepTheirFirstChoices() async throws {
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: root.appendingPathComponent("Tests/MonkeyPinyinTests/Fixtures/input-quality-v1.json")))
        let typos = corpus.cases.filter { $0.category == "typo" }
        XCTAssertEqual(typos.count, 12)
        try await MainActor.run {
            try check { session in
                for (input, expected) in [("nh", "你好"), ("xx", "谢谢"), ("hd", "好的"), ("zj", "再见"), ("mainaifen", "买奶粉"), ("bing", "并"), ("baidu", "百度")] {
                    enter(input, into: session)
                    XCTAssertEqual(session.snapshot().candidates.first, expected, input)
                }
                for item in typos {
                    enter(item.input, into: session)
                    XCTAssertTrue(item.expected.contains(session.snapshot().candidates.first ?? ""), "\(item.input): \(session.snapshot().candidates)")
                }
            }
        }
    }

    func testFrozenExactPinyinSampleRetainsTopFiveRecall() async throws {
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: root.appendingPathComponent("Tests/MonkeyPinyinTests/Fixtures/exact-pinyin-holdout-v1.json")))
        XCTAssertEqual(corpus.cases.count, 150)
        try await MainActor.run {
            try check { session in
                for item in corpus.cases {
                    enter(item.input, into: session)
                    let candidates = session.snapshot().candidates.prefix(5)
                    XCTAssertTrue(candidates.contains(where: item.expected.contains), "\(item.input): \(Array(candidates))")
                }
            }
        }
    }

    @MainActor private func check(_ body: (PinyinSession) throws -> Void) throws {
        let user = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyQuality-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: user) }
        let engine = try PinyinEngine(sharedDataURL: root.appendingPathComponent("Resources/Rime"), userDataURL: user,
                                      libraryURL: root.appendingPathComponent("Vendor/Rime/lib/librime.1.dylib"))
        let session = try engine.makeSession()
        defer { session.close() }
        try body(session)
    }

    @MainActor private func enter(_ input: String, into session: PinyinSession) {
        session.clear()
        for scalar in input.unicodeScalars { _ = session.process(key: Int32(scalar.value)) }
    }
}
