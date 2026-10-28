import XCTest
@testable import MonkeyCore

final class MixedInputPolicyTests: XCTestCase {
    func testKnownProductsOfferStandardSpellingAndKeepExplicitCase() {
        for (input, expected) in [
            ("chatgpt", "ChatGPT"), ("ChatGPT", "ChatGPT"), ("CHATGPT", "CHATGPT"),
            ("openai", "OpenAI"), ("github", "GitHub"), ("vscode", "VSCode"),
            ("swiftui", "SwiftUI"), ("macos", "macOS"), ("iphone15", "iPhone15"),
            ("iPhone15", "iPhone15"), ("api", "API"), ("API", "API")
        ] {
            XCTAssertEqual(MixedInputPolicy.candidate(for: input), expected, input)
            XCTAssertEqual(MixedInputPolicy.classify(input), .english, input)
        }
    }

    func testPinyinAndUnknownCapitalizationAreNotGuessedAsEnglish() {
        for input in ["shi", "an", "nh", "zs", "nihao", "niHao", "NIHAO", "SHI", "AN", "NH", "ai", "wo", "fooBar", "randomword"] {
            XCTAssertEqual(MixedInputPolicy.classify(input), .pinyin, input)
            XCTAssertNil(MixedInputPolicy.candidate(for: input), input)
        }
        XCTAssertEqual(MixedInputPolicy.classify("AI"), .english)
        XCTAssertEqual(MixedInputPolicy.candidate(for: "AI"), "AI")
    }

    func testDigitAfterPinyinStillSelectsCandidateButProductsAndVersionsStayLiteral() {
        for token in ["nihao", "nh", "shi", "an", "zs", "niHao", "ai"] {
            for digit in "1234567" {
                XCTAssertFalse(MixedInputPolicy.shouldStartLiteral(buffer: token, next: digit), "\(token) + \(digit)")
            }
        }
        for token in ["iPhone", "iphone", "ChatGPT", "API", "v"] {
            XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: token, next: "1"), token)
        }
        XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: "", next: "3"))
    }

    func testDomainEmailAndPathPunctuationRemainsASCII() {
        XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: "github", next: "."))
        XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: "https", next: ":"))
        XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: "www", next: "."))
        XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: "ken", next: "@"))
        XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: "~", next: "/"))
        XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: "src", next: "/"))
        for (token, kind) in [
            ("github.com", MixedInputKind.url), ("https://my-private-host.dev/path?q=你好", .url),
            ("https://my-private-host.dev/path?q=test", .url), ("ken@example.com", .email),
            ("ken@", .email), ("/Users/ken/project.swift", .filePath), ("~/Downloads/file.zip", .filePath),
            ("./Sources/main.swift", .filePath), ("~/Downloads/中文文件.zip", .filePath)
        ] {
            XCTAssertEqual(MixedInputPolicy.classify(token), kind, token)
            if kind.isStructuredLiteral {
                XCTAssertEqual(MixedInputPolicy.candidate(for: token), token)
                XCTAssertTrue(MixedInputPolicy.shouldKeepASCIIPunctuation(".", in: token), token)
            }
        }
        XCTAssertTrue(MixedInputPolicy.shouldKeepASCIIPunctuation("@", in: "ken@"))
        XCTAssertTrue(MixedInputPolicy.shouldKeepASCIIPunctuation("/", in: "https:"))
    }

    func testNormalChineseFullStopDoesNotBecomeWebsitePunctuation() {
        for token in ["nihao", "nh", "shi", "an", "wojintianxianghebeikafei", "ChatGPT"] {
            XCTAssertFalse(MixedInputPolicy.shouldStartLiteral(buffer: token, next: "."), token)
            XCTAssertFalse(MixedInputPolicy.shouldKeepASCIIPunctuation(".", in: token), token)
        }
        XCTAssertFalse(MixedInputPolicy.shouldStartLiteral(buffer: "nihao", next: "/"))
        XCTAssertFalse(MixedInputPolicy.shouldStartLiteral(buffer: "nh", next: "-"))
    }

    func testNumbersAndVersionsPreserveDecimalDotsWithoutChangingSentencePunctuation() {
        for token in ["3", "3.14", "0.2.0", "192.168.0.1", "15:30", "2026-10-29"] {
            XCTAssertEqual(MixedInputPolicy.classify(token), .number, token)
            XCTAssertTrue(MixedInputPolicy.shouldKeepASCIIPunctuation(".", in: token), token)
            XCTAssertFalse(MixedInputPolicy.shouldKeepASCIIPunctuation("?", in: token), token)
        }
        for token in ["v0", "v0.2.0", "V1.0.0-beta.1"] {
            XCTAssertEqual(MixedInputPolicy.classify(token), .version, token)
            XCTAssertEqual(MixedInputPolicy.candidate(for: token), token)
            XCTAssertTrue(MixedInputPolicy.shouldKeepASCIIPunctuation(".", in: token), token)
        }
        XCTAssertTrue(MixedInputPolicy.shouldKeepASCIIPunctuation(".", in: "", precedingText: "价格3"))
        XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: "", next: ".", precedingText: "价格3"))
        XCTAssertFalse(MixedInputPolicy.shouldKeepASCIIPunctuation(".", in: "", precedingText: "价格三"))
        XCTAssertFalse(MixedInputPolicy.shouldKeepASCIIPunctuation(".", in: "", precedingText: "3 "))
    }

    func testRecognizedLiteralKeepsItsClassificationWhileTypingPunctuation() {
        for (prefix, tail, expected) in [
            ("https", "://example.com/path?q=1", MixedInputKind.url),
            ("ken", "@example.com", .email),
            ("github", ".com/path?x=1", .url),
            ("Sources", "/MonkeyCore/file.swift", .filePath),
            ("v", "0.2.0", .version)
        ] {
            var buffer = prefix
            for (index, character) in tail.enumerated() {
                if index == 0 {
                    XCTAssertTrue(MixedInputPolicy.shouldStartLiteral(buffer: buffer, next: character), buffer)
                } else if !character.isLetter && !character.isNumber {
                    XCTAssertTrue(MixedInputPolicy.shouldKeepASCIIPunctuation(character, in: buffer), "\(buffer) + \(character)")
                }
                buffer.append(character)
                XCTAssertEqual(MixedInputPolicy.classify(buffer), expected, buffer)
            }
        }
    }

    func testWholeChineseSentencesAreNeverReclassifiedAsEnglish() {
        // The controller commits Chinese pieces and asks about only the ASCII
        // token. A future caller passing a whole sentence must not rewrite it.
        for sentence in ["访问github.com", "邮箱ken@example.com", "我用ChatGPT写SwiftUI", "wo用ChatGPT写SwiftUI"] {
            XCTAssertEqual(MixedInputPolicy.classify(sentence), .pinyin, sentence)
            XCTAssertNil(MixedInputPolicy.candidate(for: sentence), sentence)
        }
    }
}
