import CryptoKit
import Darwin
import Foundation
import MonkeyPinyin

private enum Expectation: String, Codable { case top1, top5, preserve }
private enum Layer: String, Codable { case engine, frontend }

private struct Corpus: Codable {
    let version: Int
    let title: String
    let baselineCommit: String
    let evaluationContract: String
    let cases: [InputCase]
}

private struct InputCase: Codable {
    let id: String
    let category: String
    let input: String
    let expected: [String]
    let expectation: Expectation
    let layer: Layer
    let note: String?
}

private struct Options {
    var corpus: URL
    var dataDirectory: URL
    var library: URL
    var output: URL?
    var label: String?
    var quiet = false
    var help = false
    var composition = false

    static func parse(_ arguments: [String], root: URL) throws -> Self {
        var value = Options(
            corpus: root.appendingPathComponent("Tests/MonkeyPinyinTests/Fixtures/input-quality-v1.json"),
            dataDirectory: root.appendingPathComponent("Resources/Rime"),
            library: root.appendingPathComponent("Vendor/Rime/lib/librime.1.dylib")
        )
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--help" || argument == "-h" { value.help = true; index += 1; continue }
            if argument == "--quiet" { value.quiet = true; index += 1; continue }
            if argument == "--composition" { value.composition = true; index += 1; continue }
            guard index + 1 < arguments.count else { throw Failure("Missing value for \(argument)") }
            let next = arguments[index + 1]
            switch argument {
            case "--corpus": value.corpus = URL(fileURLWithPath: next)
            case "--data-dir": value.dataDirectory = URL(fileURLWithPath: next)
            case "--library": value.library = URL(fileURLWithPath: next)
            case "--output-json": value.output = URL(fileURLWithPath: next)
            case "--label": value.label = next
            default: throw Failure("Unknown option: \(argument)")
            }
            index += 2
        }
        return value
    }
}

private struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
private protocol MeasuredSession: AnyObject {
    func process(key: Int32, modifiers: Int32) -> Bool
    func snapshot() -> PinyinSnapshot
    func takeCommit() -> String?
    func clear()
}

extension PinyinSession: MeasuredSession {}
extension CompositionSession: MeasuredSession {}

private struct Timing: Codable {
    let samples: Int
    let meanMicroseconds: Double
    let medianMicroseconds: Double
    let p95Microseconds: Double
    let p99Microseconds: Double
    let maximumMicroseconds: Double

    init(_ samples: [Double]) {
        let sorted = samples.sorted()
        self.samples = sorted.count
        meanMicroseconds = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
        func percentile(_ value: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return sorted[max(0, min(sorted.count - 1, Int(ceil(value * Double(sorted.count))) - 1))]
        }
        medianMicroseconds = percentile(0.5)
        p95Microseconds = percentile(0.95)
        p99Microseconds = percentile(0.99)
        maximumMicroseconds = sorted.last ?? 0
    }
}

private struct KeyResult: Codable {
    let key: String
    let keyCode: UInt32
    let handled: Bool
    let commit: String
    let rawPassthrough: String
    let processMicroseconds: Double
    let updateMicroseconds: Double
}

private struct CaseResult: Codable {
    let id: String
    let category: String
    let input: String
    let expected: [String]
    let expectation: Expectation
    let layer: Layer
    let evaluationScope: String
    let note: String?
    let preedit: String
    let rawInput: String
    let candidates: [String]
    let candidateComments: [String]
    let candidateCharacterLengths: [Int]
    let rankedOutputs: [String]
    let emittedOutputBeforeFinalization: String
    let expectedRank: Int?
    let top1Hit: Bool
    let top5Hit: Bool
    let engineRequirementMet: Bool?
    let preserveWithoutFinalization: Bool?
    let preserveAfterRawReturn: Bool?
    let rawReturnHandled: Bool?
    let rawReturnCommit: String?
    let outputAfterRawReturn: String?
    let preeditAfterRawReturn: String?
    let sessionCreationMicroseconds: Double
    let processTiming: Timing
    let updateTiming: Timing
    let keyResults: [KeyResult]
}

private struct Scores: Codable {
    let cases: Int
    let engineRankingCases: Int
    let engineTop1Hits: Int
    let engineTop5Hits: Int
    let engineTop1Rate: Double?
    let engineTop5Rate: Double?
    let engineRequirementsMet: Int
    let engineRequirementRate: Double?
    let frontendProbeCases: Int
    let literalPreserveProbes: Int
    let literalPreservedWithoutFinalization: Int
    let literalPreservedAfterRawReturn: Int
    let meanFirstCandidateCharacterLength: Double?
    let meanFirstRankedOutputCharacterLength: Double?

    init(_ values: [CaseResult]) {
        let ranking = values.filter { $0.layer == .engine && $0.expectation != .preserve }
        let preserve = values.filter { $0.expectation == .preserve }
        func rate(_ count: Int, _ total: Int) -> Double? { total > 0 ? Double(count) / Double(total) : nil }
        func mean(_ values: [Int]) -> Double? { values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count) }
        cases = values.count
        engineRankingCases = ranking.count
        engineTop1Hits = ranking.filter(\.top1Hit).count
        engineTop5Hits = ranking.filter(\.top5Hit).count
        engineTop1Rate = rate(engineTop1Hits, ranking.count)
        engineTop5Rate = rate(engineTop5Hits, ranking.count)
        engineRequirementsMet = ranking.filter { $0.engineRequirementMet == true }.count
        engineRequirementRate = rate(engineRequirementsMet, ranking.count)
        frontendProbeCases = values.filter { $0.layer == .frontend }.count
        literalPreserveProbes = preserve.count
        literalPreservedWithoutFinalization = preserve.filter { $0.preserveWithoutFinalization == true }.count
        literalPreservedAfterRawReturn = preserve.filter { $0.preserveAfterRawReturn == true }.count
        meanFirstCandidateCharacterLength = mean(ranking.compactMap { $0.candidates.first?.count })
        meanFirstRankedOutputCharacterLength = mean(ranking.compactMap { $0.rankedOutputs.first?.count })
    }
}

private struct Report: Codable {
    let reportVersion: Int
    let capturedAtUTC: String
    let label: String?
    let gitCommit: String?
    let workingTreeHasTrackedChanges: Bool?
    let buildConfiguration: String
    let architecture: String
    let operatingSystem: String
    let harnessSourceSHA256: String?
    let harnessBinarySHA256: String?
    let engineSourceSHA256: String?
    let bridgeSourceSHA256: String?
    let compositionSourceSHA256: String?
    let mode: String
    let corpusVersion: Int
    let corpusBaselineCommit: String
    let corpusSHA256: String
    let sourceSchemaSHA256: String?
    let deployedSchemaSHA256: String?
    let dictionaryTableSHA256: String?
    let librarySHA256: String?
    let dataDirectory: String
    let libraryPath: String
    let cleanUserProfile: Bool
    let userProfilePolicy: String
    let comparisonBoundary: String
    let engineInitializationMilliseconds: Double
    let scores: Scores
    let byCategory: [String: Scores]
    let processTiming: Timing
    let updateTiming: Timing
    let results: [CaseResult]
}

@main
private struct MonkeyBenchmark {
    @MainActor
    static func main() {
        do { try run() }
        catch {
            fputs("MonkeyBenchmark: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func run() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let options = try Options.parse(Array(CommandLine.arguments.dropFirst()), root: root)
        if options.help {
            print("""
            Usage: MonkeyBenchmark [--corpus FILE] [--data-dir DIR] [--library DYLIB]
                                   [--output-json FILE] [--label LABEL] [--quiet]
                                   [--composition]

            Uses a fresh temporary user profile, removed after the run. Exact expected
            candidate matches are reported, not used as a process exit gate. Frontend
            mixed-input cases are separate engine probes, not complete-app verdicts.
            --quiet suppresses individual console rows; JSON still contains every case.
            --composition tests only frontend-layer cases through the production
            CompositionSession with real Rime. It does not include IMK or UI delivery.
            """)
            return
        }
        let corpusData = try Data(contentsOf: options.corpus)
        let corpus = try JSONDecoder().decode(Corpus.self, from: corpusData)
        guard !corpus.cases.isEmpty else { throw Failure("Corpus is empty") }
        guard Set(corpus.cases.map(\.id)).count == corpus.cases.count else { throw Failure("Corpus case IDs are not unique") }
        guard corpus.cases.allSatisfy({ !$0.input.isEmpty && !$0.expected.isEmpty && $0.expected.allSatisfy { !$0.isEmpty } }) else {
            throw Failure("Every case needs input and at least one nonempty expected output")
        }
        // Process ranking cases before frontend probes: spaces/digits in probes
        // may commit a candidate and learn a word. They must not affect ranking.
        let selected = options.composition ? corpus.cases.filter { $0.layer == .frontend } : corpus.cases
        guard !selected.isEmpty else { throw Failure("No cases selected for this mode") }
        let ordered = selected.filter { $0.layer == .engine } + selected.filter { $0.layer == .frontend }
        let user = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyBenchmark-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: user) }
        let initializationStart = DispatchTime.now().uptimeNanoseconds
        let engine = try PinyinEngine(sharedDataURL: options.dataDirectory, userDataURL: user, libraryURL: options.library)
        let initializationMs = elapsedMicroseconds(since: initializationStart) / 1_000
        var results: [CaseResult] = []
        for item in ordered {
            let result = try measure(item, engine: engine, composition: options.composition)
            results.append(result)
            if !options.quiet { printRow(result) }
        }
        let grouped = Dictionary(grouping: results, by: \.category)
        let report = Report(
            reportVersion: 1, capturedAtUTC: ISO8601DateFormatter().string(from: Date()), label: options.label,
            gitCommit: gitOutput(root, arguments: ["rev-parse", "HEAD"]),
            workingTreeHasTrackedChanges: gitOutput(root, arguments: ["status", "--porcelain", "--untracked-files=no"]).map { !$0.isEmpty },
            buildConfiguration: buildConfiguration, architecture: architecture,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            harnessSourceSHA256: digestFile(URL(fileURLWithPath: #filePath)),
            harnessBinarySHA256: digestFile(URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()),
            engineSourceSHA256: digestFile(root.appendingPathComponent("Sources/MonkeyPinyin/PinyinEngine.swift")),
            bridgeSourceSHA256: digestFile(root.appendingPathComponent("Sources/CRimeBridge/MonkeyRime.c")),
            compositionSourceSHA256: options.composition ? digestFile(root.appendingPathComponent("Sources/MonkeyPinyin/CompositionSession.swift")) : nil,
            mode: options.composition ? "composition" : "engine",
            corpusVersion: corpus.version, corpusBaselineCommit: corpus.baselineCommit,
            corpusSHA256: digest(corpusData),
            sourceSchemaSHA256: digestFile(options.dataDirectory.appendingPathComponent("monkey_pinyin.schema.yaml")),
            deployedSchemaSHA256: digestFirstExisting([
                user.appendingPathComponent("build/monkey_pinyin.schema.yaml"),
                options.dataDirectory.appendingPathComponent("build/monkey_pinyin.schema.yaml")
            ]),
            dictionaryTableSHA256: digestFirstExisting([
                user.appendingPathComponent("build/monkey_pinyin.table.bin"),
                options.dataDirectory.appendingPathComponent("build/monkey_pinyin.table.bin")
            ]),
            librarySHA256: digestFile(options.library), dataDirectory: options.dataDirectory.standardizedFileURL.path,
            libraryPath: options.library.standardizedFileURL.path, cleanUserProfile: true,
            userProfilePolicy: "Fresh profile per run; separate session per case; no candidate acceptance in ranking cases; frontend probes run last; temporary profile removed after run.",
            comparisonBoundary: options.composition
                ? "Production CompositionSession keystrokes with real Rime, automaticEnglish=true and englishSpaceInsertsSpace=true. No IMK, UI, native event delivery or WeChat/Sogou comparison. The three Chinese-mixed ranking cases remain reference-only and do not become engine ranking passes."
                : "Monkey isolated engine only. Frontend probes are excluded from engine ranking. No WeChat/Sogou measurements are included. Timing is local and is not end-to-end keyboard/display latency.",
            engineInitializationMilliseconds: initializationMs, scores: Scores(results),
            byCategory: grouped.mapValues { Scores($0) },
            processTiming: Timing(results.flatMap { $0.keyResults.map(\.processMicroseconds) }),
            updateTiming: Timing(results.flatMap { $0.keyResults.map(\.updateMicroseconds) }), results: results
        )
        printSummary(report)
        if let output = options.output {
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            var data = try encoder.encode(report)
            data.append(0x0A)
            try data.write(to: output, options: .atomic)
            print("JSON: \(output.path)")
        }
        withExtendedLifetime(engine) {}
    }

    @MainActor
    private static func measure(_ item: InputCase, engine: PinyinEngine, composition: Bool) throws -> CaseResult {
        let creationStart = DispatchTime.now().uptimeNanoseconds
        let native = try engine.makeSession()
        let session: any MeasuredSession
        if composition {
            let production = CompositionSession(session: native)
            production.automaticEnglish = true
            production.englishSpaceInsertsSpace = true
            session = production
        } else {
            session = native
        }
        let creationMicroseconds = elapsedMicroseconds(since: creationStart)
        defer { session.clear(); native.close() }
        var output = ""
        var keys: [KeyResult] = []
        for scalar in item.input.unicodeScalars {
            let start = DispatchTime.now().uptimeNanoseconds
            let handled = session.process(key: Int32(scalar.value), modifiers: 0)
            let processMicroseconds = elapsedMicroseconds(since: start)
            let commit = session.takeCommit() ?? ""
            let raw = handled ? "" : String(scalar)
            output += commit + raw
            _ = session.snapshot() // Same candidate read that a frontend needs.
            keys.append(KeyResult(key: String(scalar), keyCode: scalar.value, handled: handled,
                                  commit: commit, rawPassthrough: raw,
                                  processMicroseconds: processMicroseconds,
                                  updateMicroseconds: elapsedMicroseconds(since: start)))
        }
        let snapshot = session.snapshot()
        var ranked = snapshot.candidates.map { output + $0 }
        if ranked.isEmpty && snapshot.preedit.isEmpty && !output.isEmpty { ranked = [output] }
        let expectedRank = ranked.firstIndex(where: item.expected.contains).map { $0 + 1 }
        let top1 = expectedRank == 1
        let top5 = expectedRank.map { $0 <= 5 } ?? false
        let before = item.expectation == .preserve ? item.expected.contains(output) && snapshot.preedit.isEmpty : nil
        var rawHandled: Bool?
        var rawCommit: String?
        var afterOutput: String?
        var afterPreedit: String?
        var afterPreserved: Bool?
        if item.expectation == .preserve {
            if !snapshot.preedit.isEmpty || !snapshot.candidates.isEmpty {
                rawHandled = session.process(key: 0xFF0D, modifiers: 0) // Explicit Return: raw composition, not first candidate.
                rawCommit = session.takeCommit() ?? ""
            }
            afterOutput = output + (rawCommit ?? "")
            afterPreedit = session.snapshot().preedit
            afterPreserved = item.expected.contains(afterOutput ?? "") && afterPreedit?.isEmpty == true
        }
        let requirement: Bool? = item.layer == .engine && item.expectation != .preserve
            ? (item.expectation == .top1 ? top1 : top5) : nil
        return CaseResult(
            id: item.id, category: item.category, input: item.input, expected: item.expected,
            expectation: item.expectation, layer: item.layer,
            evaluationScope: composition
                ? (item.expectation == .preserve ? "production-composition-keystrokes; no IMK/UI" : "production-composition-reference-only; no IMK/UI")
                : (item.layer == .engine ? "engine-ranking" : "engine-probe-only; frontend validation required"),
            note: item.note, preedit: snapshot.preedit, rawInput: snapshot.rawInput,
            candidates: snapshot.candidates, candidateComments: snapshot.comments,
            candidateCharacterLengths: snapshot.candidates.map(\.count), rankedOutputs: ranked,
            emittedOutputBeforeFinalization: output, expectedRank: expectedRank, top1Hit: top1, top5Hit: top5,
            engineRequirementMet: requirement, preserveWithoutFinalization: before,
            preserveAfterRawReturn: afterPreserved, rawReturnHandled: rawHandled, rawReturnCommit: rawCommit,
            outputAfterRawReturn: afterOutput, preeditAfterRawReturn: afterPreedit,
            sessionCreationMicroseconds: creationMicroseconds,
            processTiming: Timing(keys.map(\.processMicroseconds)), updateTiming: Timing(keys.map(\.updateMicroseconds)),
            keyResults: keys
        )
    }

    private static func printRow(_ result: CaseResult) {
        if result.evaluationScope.hasPrefix("production-composition") {
            if result.expectation == .preserve {
                print("[\(result.category)] \(result.input) → \(result.outputAfterRawReturn ?? "") | production composition raw-Return exact=\(result.preserveAfterRawReturn == true)")
            } else {
                print("[\(result.category)] \(result.input) → \(result.rankedOutputs.first ?? "<no candidate>") | composition reference only, not an acceptance pass")
            }
            return
        }
        let output = result.rankedOutputs.first ?? "<no candidate>"
        let scope = result.layer == .engine ? "rank=\(result.expectedRank.map(String.init) ?? "miss")" : "frontend probe"
        print("[\(result.category)] \(result.input) → \(output) | \(scope) | top1=\(result.top1Hit) top5=\(result.top5Hit)")
    }

    private static func printSummary(_ report: Report) {
        let scores = report.scores
        func percent(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0 * 100) } ?? "n/a" }
        if report.mode == "composition" {
            print("Production composition: \(scores.cases) frontend cases; IMK/UI delivery excluded; Chinese-mixed ranking cases are reference-only")
            print("Literal preserved automatically \(scores.literalPreservedWithoutFinalization)/\(scores.literalPreserveProbes), after explicit raw Return \(scores.literalPreservedAfterRawReturn)/\(scores.literalPreserveProbes)")
        } else {
            print("Engine ranking: \(scores.engineRankingCases) cases; top1 \(scores.engineTop1Hits) (\(percent(scores.engineTop1Rate))); top5 \(scores.engineTop5Hits) (\(percent(scores.engineTop5Rate)))")
            print("Requirements met: \(scores.engineRequirementsMet)/\(scores.engineRankingCases) (\(percent(scores.engineRequirementRate)))")
            print("Frontend probes: \(scores.frontendProbeCases), excluded from ranking; literal preserved automatically \(scores.literalPreservedWithoutFinalization)/\(scores.literalPreserveProbes), after explicit raw Return \(scores.literalPreservedAfterRawReturn)/\(scores.literalPreserveProbes)")
        }
        print(String(format: "Process latency: median %.2f µs, p95 %.2f µs, p99 %.2f µs, max %.2f µs", report.processTiming.medianMicroseconds, report.processTiming.p95Microseconds, report.processTiming.p99Microseconds, report.processTiming.maximumMicroseconds))
        print(String(format: "Process + commit/snapshot read: p95 %.2f µs; engine initialization %.2f ms", report.updateTiming.p95Microseconds, report.engineInitializationMilliseconds))
        for category in report.byCategory.keys.sorted() {
            let value = report.byCategory[category]!
            if report.mode == "composition" {
                print("  \(category): exact after raw Return \(value.literalPreservedAfterRawReturn)/\(value.literalPreserveProbes); reference-only cases \(value.cases - value.literalPreserveProbes)")
            } else {
                print("  \(category): top1 \(value.engineTop1Hits)/\(value.engineRankingCases), top5 \(value.engineTop5Hits)/\(value.engineRankingCases); frontend probes \(value.frontendProbeCases)")
            }
        }
    }

    private static func elapsedMicroseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func digestFile(_ url: URL) -> String? { (try? Data(contentsOf: url)).map(digest) }
    private static func digestFirstExisting(_ urls: [URL]) -> String? { urls.lazy.compactMap(digestFile).first }
    private static var buildConfiguration: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "other"
        #endif
    }
    private static func gitOutput(_ root: URL, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
