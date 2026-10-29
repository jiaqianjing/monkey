import AppKit
import Darwin
import MonkeyCore
import MonkeyPinyin

/// An isolated layout probe. It renders the production panel with a real engine,
/// but never registers an input service, loads an account, or edits a client.
@MainActor
enum PreviewCommand {
    private static var retainedDelegate: CandidatePreviewDelegate?

    static func runIfRequested(_ arguments: [String]) -> Bool {
        guard arguments.contains("--preview-candidates") else { return false }
        let app = NSApplication.shared
        let delegate = CandidatePreviewDelegate(arguments: arguments)
        retainedDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
        delegate.cleanup()
        retainedDelegate = nil
        return true
    }
}

@MainActor
private final class CandidatePreviewDelegate: NSObject, NSApplicationDelegate {
    private let arguments: [String]
    private var engine: PinyinEngine?
    private var nativeSession: PinyinSession?
    private var session: CompositionSession?
    private var panel: CandidatePanel?
    private var temporaryUserDirectory: URL?
    private var input = "nihao"
    private var translationMode = false
    private var draft = TranslationDraft()
    private var lastAction: String?
    private var durationTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    init(arguments: [String]) { self.arguments = arguments }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            input = try option("--preview-input") ?? "nihao"
            translationMode = arguments.contains("--preview-translation")
            guard input.utf8.count <= 512 else { throw PreviewError("预览输入最多 512 个 UTF-8 字节。") }
            guard let resources = Bundle.main.resourceURL, let frameworks = Bundle.main.privateFrameworksURL else {
                throw PreviewError("请从已打包的 Monkey.app 运行候选预览。")
            }
            let shared = resources.appendingPathComponent("Rime", isDirectory: true)
            let library = frameworks.appendingPathComponent("librime.1.dylib")
            guard FileManager.default.fileExists(atPath: shared.path), FileManager.default.fileExists(atPath: library.path) else {
                throw PreviewError("预览需要应用内的 Rime 资源和 librime 运行库。")
            }
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent("Monkey-CandidatePreview-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            temporaryUserDirectory = temporary
            let engine = try PinyinEngine(sharedDataURL: shared, userDataURL: temporary, libraryURL: library)
            let native = try engine.makeSession()
            self.engine = engine
            nativeSession = native
            session = CompositionSession(session: native)
            feedInitialInput()

            if translationMode { prepareTranslationFixture() }
            let panel = CandidatePanel()
            panel.title = "Monkey 候选预览"
            panel.setAccessibilityLabel("Monkey 候选预览")
            self.panel = panel
            installMenu()
            installTerminationSignals()
            if let durationString = try option("--preview-duration") {
                guard let duration = Double(durationString), duration > 0, duration <= 3600 else {
                    throw PreviewError("--preview-duration 必须是 0 到 3600 之间的秒数。")
                }
                durationTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
                    Task { @MainActor in NSApp.terminate(nil) }
                }
            }
            render()
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            fputs("Monkey candidate preview: \(error.localizedDescription)\n", stderr)
            cleanup()
            NSApp.stop(nil)
            // A command-line probe must report unavailable resources as failure.
            exit(EXIT_FAILURE)
        }
    }

    func applicationWillTerminate(_ notification: Notification) { cleanup() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func cleanup() {
        durationTimer?.invalidate()
        durationTimer = nil
        for source in signalSources { source.cancel() }
        signalSources.removeAll()
        panel?.orderOut(nil)
        panel = nil
        session?.clear()
        nativeSession?.close()
        session = nil
        nativeSession = nil
        engine = nil
        if let temporary = temporaryUserDirectory {
            try? FileManager.default.removeItem(at: temporary)
            temporaryUserDirectory = nil
        }
    }

    private func render() {
        guard let panel, let session else { return }
        let snapshot = session.snapshot()
        let explanation = translationMode
            ? "仅布局示例 · 示例译文不会联网生成，也不会写入其他应用"
            : "独立临时词库 · 仅检查候选布局，不验证实体按键"
        let message = lastAction.map { "\(explanation) · \($0)" } ?? explanation
        panel.update(preedit: snapshot.preedit, candidates: snapshot.candidates, comments: snapshot.comments,
                     highlighted: snapshot.highlightedIndex, pageNumber: snapshot.page, isLastPage: snapshot.isLastPage,
                     literal: session.isLiteral, asciiMode: false, translationMode: translationMode,
                     draft: draft, message: message, cursor: .zero,
                     onChoose: { [weak self] index in self?.choose(index) },
                     onForget: { [weak self] index in self?.forget(index) },
                     onPage: { [weak self] backward in self?.page(backward: backward) },
                     onConfirm: { [weak self] in self?.recordFixtureAction("已点击英文确认（仅布局）") },
                     onChinese: { [weak self] in self?.recordFixtureAction("已点击中文确认（仅布局）") },
                     onToggleTranslation: { [weak self] in self?.toggleTranslationFixture() })
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                     y: visible.midY - panel.frame.height / 2))
    }

    private func choose(_ index: Int) {
        guard let session, session.selectCandidate(index) else { return }
        if let commit = session.takeCommit() { lastAction = "临时会话已选：\(commit)" }
        if session.snapshot().preedit.isEmpty { feedInitialInput() }
        render()
    }

    private func forget(_ index: Int) {
        guard let session else { return }
        lastAction = session.forgetCandidate(index) ? "已删除临时学习记录" : "该候选没有可删除的临时学习记录"
        render()
    }

    private func page(backward: Bool) {
        _ = session?.changePage(backward: backward)
        lastAction = backward ? "上一页" : "下一页"
        render()
    }

    private func recordFixtureAction(_ description: String) {
        lastAction = description
        render()
    }

    private func prepareTranslationFixture() {
        // These are labeled layout fixtures, never account-backed inference.
        session?.clear()
        draft.replaceSource("明天下午我有空，我们把会议改到三点吧。")
        if let request = draft.beginRequest() {
            draft.complete("I’m free tomorrow afternoon. Let’s move the meeting to 3:00 p.m.", for: request)
        }
    }

    private func toggleTranslationFixture() {
        translationMode.toggle()
        draft.reset()
        if translationMode { prepareTranslationFixture() }
        else { feedInitialInput() }
        render()
    }

    private func feedInitialInput() {
        guard let session else { return }
        for scalar in input.unicodeScalars {
            _ = session.process(key: Int32(scalar.value))
            _ = session.takeCommit()
        }
    }

    private func installMenu() {
        let menu = NSMenu()
        let application = NSMenuItem()
        let actions = NSMenu(title: "Monkey 候选预览")
        let quit = NSMenuItem(title: "退出候选预览", action: #selector(quitPreview), keyEquivalent: "q")
        quit.target = self
        actions.addItem(quit)
        application.submenu = actions
        menu.addItem(application)
        NSApp.mainMenu = menu
    }

    @objc private func quitPreview() { NSApp.terminate(nil) }

    private func installTerminationSignals() {
        for identifier in [SIGINT, SIGTERM] {
            Darwin.signal(identifier, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: identifier, queue: .main)
            source.setEventHandler { Task { @MainActor in NSApp.terminate(nil) } }
            signalSources.append(source)
            source.resume()
        }
    }

    private func option(_ name: String) throws -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
            throw PreviewError("\(name) 缺少参数。")
        }
        return arguments[index + 1]
    }
}

private struct PreviewError: LocalizedError {
    let description: String
    init(_ description: String) { self.description = description }
    var errorDescription: String? { description }
}
