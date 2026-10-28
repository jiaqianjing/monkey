import AppKit
import InputMethodKit
import MonkeyCore
import MonkeyPinyin
import os

@objc(MonkeyInputController)
@MainActor
final class MonkeyInputController: IMKInputController {
    private var session: CompositionSession?
    private let panel = CandidatePanel()
    private var draft = TranslationDraft()
    private var translationMode = false
    private var asciiMode = false
    private var active = false
    private var inputClient: IMKTextInput?
    private var requestTask: Task<Void, Never>?
    private var message: String?
    private var markedText = ""
    private var markedCaret = 0
    private var activation = UUID()
    private var recoverableDraft = ""
    private let logger = Logger(subsystem: "org.monkey.inputmethod.Monkey", category: "InputSession")
    private var receivedFirstKey = false

    override func activateServer(_ sender: Any!) {
        if let client = client() { bind(client) }
        active = true
        activation = UUID()
        if session == nil { session = AppRuntime.makeSession().map { CompositionSession(session: $0) } }
        logger.notice("Input session activated; engine ready: \(self.session != nil, privacy: .public)")
        if translationMode { ChatGPTClient.shared.reloadAccount() }
        message = AppRuntime.engineError
        refresh()
    }

    override func deactivateServer(_ sender: Any!) {
        // The original client still owns its marked text at this point.
        // Commit only the source; an asynchronous English result is never committed here.
        if !markedText.isEmpty { commitOriginal() }
        invalidateAsyncWork()
        session?.clear()
        draft.reset()
        panel.orderOut(nil)
        inputClient = nil
        markedText = ""
        markedCaret = 0
        active = false
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, event.type == .keyDown, let client = client() else { return false }
        if !receivedFirstKey {
            logger.notice("First keyboard event received by input session")
            receivedFirstKey = true
        }
        bind(client)
        active = true
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plain = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags.contains([.control, .shift]), !flags.contains(.command), plain == "t" {
            toggleTranslation()
            return true
        }
        if event.keyCode == 49, flags.contains(.shift), !flags.contains(.control), !flags.contains(.option), !flags.contains(.command) {
            toggleASCII()
            return true
        }
        if flags.contains(.command) {
            if !markedText.isEmpty { commitOriginal() }
            return false
        }
        guard let session else {
            message = AppRuntime.engineError
            refresh()
            return false
        }
        session.automaticEnglish = TypingPreferences.automaticEnglish
        session.englishSpaceInsertsSpace = TypingPreferences.englishSpaceInsertsSpace
        message = nil
        let before = session.snapshot()
        let returnKey = event.keyCode == 36 || event.keyCode == 76
        if translationMode && returnKey && flags.contains(.shift) {
            commitOriginal()
            return true
        }
        if translationMode && returnKey && flags.contains(.control) {
            confirmEnglish()
            return true
        }
        // Preserve navigation and system shortcuts, but never strand a Chinese draft.
        if flags.contains(.control) || flags.contains(.option) {
            if !markedText.isEmpty { commitOriginal() }
            return false
        }
        if translationMode {
            if event.keyCode == 53 {
                guard !before.preedit.isEmpty || !draft.source.isEmpty else { return false }
                if !before.preedit.isEmpty {
                    session.clear()
                    if !draft.source.isEmpty { scheduleTranslation() }
                }
                else { invalidateAsyncWork(); draft.cancel(); message = "翻译已取消，中文草稿仍保留" }
                refresh()
                return true
            }
            if event.keyCode == 51 && before.preedit.isEmpty && !draft.source.isEmpty {
                draft.removeLastCharacter()
                scheduleTranslation()
                refresh()
                return true
            }
            if returnKey && before.preedit.isEmpty && !draft.source.isEmpty {
                message = "Control + Return 输入英文；Shift + Return 输入中文"
                if !draft.canConfirm { scheduleTranslation(immediate: true) }
                refresh()
                return true
            }
            if [123, 124, 125, 126, 115, 119, 116, 121].contains(event.keyCode), before.preedit.isEmpty, !draft.source.isEmpty {
                // First finish this single-sentence draft before moving the host caret.
                commitOriginal()
                return false
            }
        }
        if asciiMode {
            if translationMode, let text = event.characters, !text.isEmpty,
               text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                draft.append(text)
                scheduleTranslation()
                refresh()
                return true
            }
            message = nil
            refresh()
            return false
        }
        guard let key = rimeKey(event) else { return false }
        let handled = session.process(key: key, modifiers: flags.contains(.shift) ? 1 : 0)
        if let commit = session.takeCommit(), !commit.isEmpty {
            if translationMode { draft.append(commit); scheduleTranslation() }
            else { insert(commit) }
        }
        let after = session.snapshot()
        if translationMode {
            if !handled, let text = event.characters, !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                draft.append(text)
                scheduleTranslation()
                refresh()
                return true
            }
            if !after.preedit.isEmpty {
                invalidateAsyncWork()
                draft.invalidate()
            } else if !draft.source.isEmpty && draft.status == .waiting {
                scheduleTranslation()
            }
        }
        refresh()
        return handled
    }

    override func commitComposition(_ sender: Any!) {
        if let client = client() { bind(client) }
        commitOriginal()
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu(title: "Monkey")
        let english = NSMenuItem(title: asciiMode ? "切换中文拼音  ⇧Space" : "切换英文直输  ⇧Space", action: #selector(toggleASCIIFromMenu(_:)), keyEquivalent: "")
        english.target = self
        menu.addItem(english)
        let translate = NSMenuItem(title: translationMode ? "关闭中 → 英翻译" : "开启中 → 英翻译  ⌃⇧T", action: #selector(toggleTranslationFromMenu(_:)), keyEquivalent: "")
        translate.target = self
        translate.state = translationMode ? .on : .off
        menu.addItem(translate)
        if !recoverableDraft.isEmpty {
            let recover = NSMenuItem(title: "恢复上一条中文草稿", action: #selector(recoverDraft(_:)), keyEquivalent: "")
            recover.target = self
            menu.addItem(recover)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Monkey 设置…", action: #selector(showPreferences(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        return menu
    }

    override func showPreferences(_ sender: Any!) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--settings"]
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
    }

    @objc private func toggleTranslationFromMenu(_ sender: Any?) { toggleTranslation() }
    @objc private func toggleASCIIFromMenu(_ sender: Any?) { toggleASCII() }

    @objc private func recoverDraft(_ sender: Any?) {
        guard active, !recoverableDraft.isEmpty else { return }
        if !markedText.isEmpty { commitOriginal() }
        translationMode = true
        asciiMode = false
        draft.replaceSource(recoverableDraft)
        recoverableDraft = ""
        scheduleTranslation()
        refresh()
    }

    private func bind(_ client: IMKTextInput) {
        if let previous = inputClient, (previous as AnyObject) !== (client as AnyObject) {
            // A different client must never inherit the old marked text or a pending result.
            // Retain a local, explicit recovery action instead of writing into the new field.
            let source = (translationMode ? draft.source : "") + (session?.snapshot().preedit ?? "")
            if !source.isEmpty { recoverableDraft = source }
            invalidateAsyncWork()
            session?.clear()
            draft.reset()
            markedText = ""
            markedCaret = 0
            activation = UUID()
            panel.orderOut(nil)
        }
        inputClient = client
    }

    private func toggleASCII() {
        if translationMode, let session {
            if !session.snapshot().preedit.isEmpty {
                _ = session.commitComposition()
                if let text = session.takeCommit() { draft.append(text) }
                session.clear()
                scheduleTranslation()
            }
        } else if !markedText.isEmpty { commitOriginal() }
        asciiMode.toggle()
        message = asciiMode ? "英文直输 · Shift + Space 返回拼音" : "中文拼音"
        refresh()
    }

    private func toggleTranslation() {
        if !markedText.isEmpty { commitOriginal() }
        translationMode.toggle()
        message = nil
        if translationMode {
            ChatGPTClient.shared.reloadAccount()
            if ChatGPTClient.shared.accountEmail == nil { message = "请在 Monkey 设置中登录 ChatGPT；中文输入仍可使用" }
        }
        refresh()
    }

    private func selectCandidate(_ index: Int) {
        guard active, let session, session.selectCandidate(index) else { return }
        if let commit = session.takeCommit(), !commit.isEmpty {
            if translationMode { draft.append(commit); scheduleTranslation() }
            else { insert(commit) }
        }
        if translationMode && !session.snapshot().preedit.isEmpty {
            invalidateAsyncWork()
            draft.invalidate()
        }
        refresh()
    }

    private func forgetCandidate(_ index: Int) {
        guard active, let session else { return }
        // Rime reports event acceptance; read-only table candidates may ignore it.
        message = session.forgetCandidate(index) ? "已尝试清除个人学习记录，内置词库保留" : "该词没有可删除的个人学习记录，内置词库保留"
        refresh()
    }

    private func changePage(backward: Bool) {
        guard active, session?.changePage(backward: backward) == true else { return }
        refresh()
    }

    private func scheduleTranslation(immediate: Bool = false) {
        invalidateAsyncWork()
        message = nil
        guard active, translationMode, !draft.source.isEmpty, session?.snapshot().preedit.isEmpty != false else { return }
        let currentActivation = activation
        let sourceRevision = draft.revision
        requestTask = Task { [weak self] in
            do {
                if !immediate { try await Task.sleep(nanoseconds: 650_000_000) }
                guard !Task.isCancelled, let self, self.active, self.activation == currentActivation,
                      self.draft.revision == sourceRevision, let request = self.draft.beginRequest() else { return }
                self.refresh()
                do {
                    var preview = ""
                    let translated = try await ChatGPTClient.shared.translate(request.source) { [weak self] delta in
                        guard let self, self.active, self.activation == currentActivation else { return }
                        preview += delta
                        if self.draft.receivePreview(preview, for: request) { self.refresh() }
                    }
                    guard !Task.isCancelled, self.active, self.activation == currentActivation else { return }
                    self.draft.complete(translated, for: request)
                    self.refresh()
                } catch {
                    guard !Task.isCancelled, self.active, self.activation == currentActivation else { return }
                    self.draft.fail(error.localizedDescription, for: request)
                    self.refresh()
                }
            } catch { /* A newer revision or focus change cancelled the debounce. */ }
        }
    }

    private func confirmEnglish() {
        guard active, translationMode, session?.snapshot().preedit.isEmpty != false, draft.canConfirm else {
            message = "请先完成选词，并等待本句翻译完成"
            refresh()
            return
        }
        let english = draft.translation
        invalidateAsyncWork()
        session?.clear()
        draft.reset()
        insert(english)
        message = nil
        refresh()
    }

    private func commitOriginal() {
        guard let session else { return }
        let snapshot = session.snapshot()
        var text = translationMode ? draft.source : ""
        if !snapshot.preedit.isEmpty {
            _ = session.commitComposition()
            text += session.takeCommit() ?? snapshot.preedit
        }
        invalidateAsyncWork()
        session.clear()
        draft.reset()
        if !text.isEmpty { insert(text) }
        else if !markedText.isEmpty { mark("") }
        panel.orderOut(nil)
        message = nil
    }

    private func invalidateAsyncWork() {
        requestTask?.cancel()
        requestTask = nil
    }

    private func insert(_ text: String) {
        inputClient?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        markedText = ""
        markedCaret = 0
    }

    private func mark(_ text: String, caret: Int? = nil) {
        let caret = max(0, min(caret ?? text.utf16.count, text.utf16.count))
        guard text != markedText || caret != markedCaret else { return }
        inputClient?.setMarkedText(text, selectionRange: NSRange(location: caret, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        markedText = text
        markedCaret = caret
    }

    private func refresh() {
        guard active, let inputClient else { panel.orderOut(nil); return }
        let snapshot = session?.snapshot()
        let preedit = snapshot?.preedit ?? ""
        mark((translationMode ? draft.source : "") + preedit,
             caret: (translationMode ? draft.source.utf16.count : 0) + (snapshot?.caretUTF16 ?? 0))
        if !translationMode && preedit.isEmpty && message == nil {
            panel.orderOut(nil)
            return
        }
        var rect = NSRect.zero
        _ = inputClient.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        panel.update(preedit: preedit, candidates: snapshot?.candidates ?? [], comments: snapshot?.comments ?? [],
                     highlighted: snapshot?.highlightedIndex ?? 0, pageNumber: snapshot?.page ?? 0,
                     isLastPage: snapshot?.isLastPage ?? true, literal: session?.isLiteral ?? false,
                     asciiMode: asciiMode,
                     translationMode: translationMode, draft: draft, message: message, cursor: rect,
                     onChoose: { [weak self] in self?.selectCandidate($0) },
                     onForget: { [weak self] in self?.forgetCandidate($0) },
                     onPage: { [weak self] in self?.changePage(backward: $0) },
                     onConfirm: { [weak self] in self?.confirmEnglish() },
                     onChinese: { [weak self] in self?.commitOriginal(); self?.refresh() })
    }

    private func rimeKey(_ event: NSEvent) -> Int32? {
        switch event.keyCode {
        case 36, 76: return 0xff0d
        case 48: return 0xff09
        case 51: return 0xff08
        case 53: return 0xff1b
        case 117: return 0xffff
        case 123: return 0xff51
        case 124: return 0xff53
        case 125: return 0xff54
        case 126: return 0xff52
        case 116: return 0xff55
        case 121: return 0xff56
        case 115: return 0xff50
        case 119: return 0xff57
        default:
            guard let value = event.characters?.unicodeScalars.first?.value, value < 0x100 else { return nil }
            return Int32(value)
        }
    }
}
