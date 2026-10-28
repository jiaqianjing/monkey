import Foundation
import MonkeyCore

/// The production keystroke path shared by IMK and real-engine integration tests.
/// Structured ASCII tokens stay in a local composition, so Rime cannot turn an
/// address's dots into Chinese punctuation or its digits into candidate choices.
@MainActor
public final class CompositionSession {
    private let pinyin: PinyinSession
    private var literal: String?
    private var literalCaret = 0
    private var possibleAddress = false
    private var pendingCommit = ""
    private var cachedSnapshot: PinyinSnapshot?
    public var automaticEnglish = true
    public var englishSpaceInsertsSpace = true
    public var isLiteral: Bool { literal != nil }

    public init(session: PinyinSession) { pinyin = session }

    public func snapshot() -> PinyinSnapshot {
        if let cachedSnapshot { return cachedSnapshot }
        guard let literal else {
            let value = pinyin.snapshot()
            cachedSnapshot = value
            return value
        }
        let canonical = MixedInputPolicy.candidate(for: literal) ?? literal
        let choices = canonical == literal ? [literal] : [canonical, literal]
        let value = PinyinSnapshot(preedit: literal, candidates: choices, rawInput: literal,
                              comments: choices.enumerated().map { $0.offset == 0 && canonical != literal ? "英文" : "原文" },
                              caretUTF16: literalCaret, rawCaret: literalCaret)
        cachedSnapshot = value
        return value
    }

    @discardableResult
    public func process(key: Int32, modifiers: Int32 = 0) -> Bool {
        if literal != nil { cachedSnapshot = nil; return processLiteral(key: key, modifiers: modifiers) }
        let before = snapshot()
        cachedSnapshot = nil
        let atEnd = before.rawCaret == before.rawInput.utf8.count
        let selected = before.candidates.indices.contains(before.highlightedIndex) ? before.candidates[before.highlightedIndex] : ""
        if modifiers & ~Int32(1) == 0, key >= 0x21, key <= 0x7e,
           atEnd, let scalar = UnicodeScalar(UInt32(key)), !before.preedit.unicodeScalars.contains(where: Self.isHan) {
            let character = Character(scalar)
            let prospective = before.rawInput + String(character)
            let kind = MixedInputPolicy.classify(prospective)
            // Keep '/' available for the normal Chinese punctuation candidates.
            let symbolTrigger = MixedInputPolicy.shouldStartLiteral(buffer: before.rawInput, next: character)
            let explicitProduct = automaticEnglish && kind == .english &&
                (Self.hasUppercase(prospective) || MixedInputPolicy.candidate(for: before.rawInput).map(Self.hasUppercase) == true)
            let cSymbol = (before.rawInput.lowercased() == "c" && ["+", "#"].contains(character)) ||
                (before.rawInput == "C+" && character == "+")
            // A complete English word followed by identifier punctuation can
            // be an email local part (first.last+tag), without guessing from a
            // Chinese spelling such as nihao. The dictionary supplies evidence.
            let address = automaticEnglish && before.rawInput.count >= 3 &&
                [".", "+", "_"].contains(character) && selected == before.rawInput && Self.isASCIIWord(selected)
            let structured = (before.rawInput.isEmpty && character == "~") ||
                (!(before.rawInput.isEmpty && character == "/") && symbolTrigger &&
                 (kind.isStructuredLiteral || explicitProduct || cSymbol)) || address
            if structured {
                pinyin.clear()
                literal = prospective
                literalCaret = prospective.utf16.count
                possibleAddress = address
                return true
            }
        }
        let englishSpace = key == 32 && automaticEnglish && englishSpaceInsertsSpace && Self.isASCIIWord(selected)
        let handled = pinyin.process(key: key, modifiers: modifiers)
        drainPinyinCommit()
        let after = pinyin.snapshot()
        cachedSnapshot = after
        if englishSpace && handled && after.preedit.isEmpty && pendingCommit.hasSuffix(selected) { pendingCommit += " " }
        // Only a complete known token with explicit capitalization can switch
        // early. Lowercase prefixes stay in Rime: main+aifen must be 买奶粉.
        if automaticEnglish, atEnd, after.rawInput.count >= 3, Self.hasUppercase(after.rawInput),
           after.rawInput == before.rawInput + (UnicodeScalar(UInt32(max(0, key))).map(String.init) ?? ""),
           MixedInputPolicy.classify(after.rawInput) == .english,
           MixedInputPolicy.candidate(for: after.rawInput) != nil,
           !after.preedit.unicodeScalars.contains(where: Self.isHan) {
            literal = after.rawInput
            literalCaret = after.rawInput.utf16.count
            possibleAddress = false
            pinyin.clear()
            cachedSnapshot = nil
        }
        return handled
    }

    public func takeCommit() -> String? {
        drainPinyinCommit()
        guard !pendingCommit.isEmpty else { return nil }
        defer { pendingCommit = "" }
        return pendingCommit
    }

    public func clear() {
        cachedSnapshot = nil
        pinyin.clear()
        literal = nil
        literalCaret = 0
        possibleAddress = false
        pendingCommit = ""
    }

    @discardableResult
    public func commitComposition() -> Bool {
        cachedSnapshot = nil
        if let literal {
            finishLiteral(MixedInputPolicy.candidate(for: literal) ?? literal)
            return true
        }
        let handled = pinyin.commitComposition()
        drainPinyinCommit()
        return handled
    }

    @discardableResult
    public func selectCandidate(_ index: Int) -> Bool {
        if literal != nil {
            let choices = snapshot().candidates
            guard choices.indices.contains(index) else { return false }
            finishLiteral(choices[index])
            return true
        }
        cachedSnapshot = nil
        let handled = pinyin.selectCandidate(index)
        drainPinyinCommit()
        return handled
    }

    @discardableResult
    public func forgetCandidate(_ index: Int) -> Bool {
        cachedSnapshot = nil
        return !isLiteral && pinyin.forgetCandidate(index)
    }

    @discardableResult
    public func changePage(backward: Bool) -> Bool {
        cachedSnapshot = nil
        return !isLiteral && pinyin.changePage(backward: backward)
    }

    private func processLiteral(key: Int32, modifiers: Int32) -> Bool {
        guard var text = literal else { return false }
        switch key {
        case 0xff1b:
            literal = nil
            literalCaret = 0
            possibleAddress = false
            return true
        case 0xff08:
            if literalCaret > 0 {
                let end = text.index(text.startIndex, offsetBy: literalCaret)
                text.remove(at: text.index(before: end))
                literalCaret -= 1
            }
            literal = text.isEmpty ? nil : text
            if text.isEmpty { possibleAddress = false }
            return true
        case 0xffff:
            if literalCaret < text.count { text.remove(at: text.index(text.startIndex, offsetBy: literalCaret)) }
            literal = text.isEmpty ? nil : text
            if text.isEmpty { possibleAddress = false }
            return true
        case 0xff51: literalCaret = max(0, literalCaret - 1); return true
        case 0xff53: literalCaret = min(text.count, literalCaret + 1); return true
        case 0xff50: literalCaret = 0; return true
        case 0xff57: literalCaret = text.count; return true
        case 0xff52, 0xff54, 0xff55, 0xff56: return true
        case 0xff0d, 0xff09:
            // Return is an explicit original-text commit, never a host newline.
            finishLiteral(text)
            return true
        case 0x20:
            let kind = MixedInputPolicy.classify(text)
            let selected = kind == .english ? (MixedInputPolicy.candidate(for: text) ?? text) : text
            finishLiteral(selected + (kind != .english || englishSpaceInsertsSpace ? " " : ""))
            return true
        default: break
        }
        guard key >= 0x21, key <= 0x7e, let scalar = UnicodeScalar(UInt32(key)) else {
            finishLiteral(text)
            let handled = pinyin.process(key: key, modifiers: modifiers)
            drainPinyinCommit()
            return handled
        }
        let character = Character(scalar)
        let isAlphanumeric = CharacterSet.alphanumerics.contains(scalar)
        if literalCaret == text.count, CharacterSet.letters.contains(scalar),
           let split = Self.numericParts(text) {
            let suffix = split.suffix + String(character)
            if !Self.unitPrefixes.contains(suffix.lowercased()) {
                // Numbers can be followed directly by pinyin: 2026nian / 10dian.
                // A short unit prefix is deferred so 3.5kg / 16GB remain ASCII.
                finishLiteral(split.number)
                for letter in suffix.unicodeScalars {
                    let handled = pinyin.process(key: Int32(letter.value), modifiers: modifiers)
                    drainPinyinCommit()
                    if !handled { pendingCommit += String(letter) }
                }
                return true
            }
        }
        let kind = MixedInputPolicy.classify(text)
        let addressPunctuation = possibleAddress && ".@_+-!#$%&'*=/^`{|}~".contains(character)
        if isAlphanumeric || addressPunctuation || MixedInputPolicy.shouldKeepASCIIPunctuation(character, in: text) ||
            (!kind.isStructuredLiteral && MixedInputPolicy.shouldStartLiteral(buffer: text, next: character)) {
            text.insert(character, at: text.index(text.startIndex, offsetBy: literalCaret))
            literalCaret += 1
            literal = text
            return true
        }
        // Sentence punctuation terminates English, then uses the Chinese rules.
        finishLiteral(MixedInputPolicy.candidate(for: text) ?? text)
        let handled = pinyin.process(key: key, modifiers: modifiers)
        drainPinyinCommit()
        return handled
    }

    private func finishLiteral(_ text: String) {
        cachedSnapshot = nil
        pendingCommit += text
        literal = nil
        literalCaret = 0
        possibleAddress = false
    }

    private func drainPinyinCommit() {
        if let text = pinyin.takeCommit() { pendingCommit += text }
    }

    private static func isHan(_ scalar: UnicodeScalar) -> Bool {
        (0x3400...0x9fff).contains(scalar.value) || (0x20000...0x3134f).contains(scalar.value)
    }

    private static func hasUppercase(_ text: String) -> Bool { text.utf8.contains { (65...90).contains($0) } }
    private static func isASCIIWord(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || $0 == 39 || $0 == 45 }
    }

    private static let unitPrefixes: Set<String> = {
        let units = ["s", "ms", "ns", "min", "h", "km", "m", "cm", "mm", "kg", "g", "ml", "l", "kb", "mb", "gb", "tb", "px", "pt", "dpi", "hz", "khz", "mhz", "ghz", "fps", "rmb", "usd", "cny", "eur", "am", "pm"]
        return Set(units.flatMap { word in (1...word.count).map { String(word.prefix($0)) } })
    }()

    private static func numericParts(_ text: String) -> (number: String, suffix: String)? {
        let number = String(text.prefix { "0123456789.+-:%".contains($0) })
        guard MixedInputPolicy.classify(number) == .number else { return nil }
        let suffix = String(text.dropFirst(number.count))
        guard suffix.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        return (number, suffix)
    }
}
