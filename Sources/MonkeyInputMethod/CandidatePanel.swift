import AppKit
import MonkeyCore

private final class CandidateSurface: NSVisualEffectView {
    override var isFlipped: Bool { true }
}

/// Input-method panels intentionally never become key. Native inline button cells
/// otherwise draw their titles as inactive even when the actions are enabled.
private final class CandidateButton: NSButton {
    enum Emphasis { case plain, accent, tinted, outlined }
    var emphasis: Emphasis = .plain { didSet { needsDisplay = true } }

    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor.controlAccentColor
        let background = bounds.insetBy(dx: 1, dy: 2)
        let shape = NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5)
        let foreground: NSColor
        if !isEnabled {
            foreground = .disabledControlTextColor
            if emphasis != .plain {
                NSColor.quaternaryLabelColor.withAlphaComponent(0.10).setFill()
                shape.fill()
            }
        } else {
            switch emphasis {
            case .accent:
                accent.withAlphaComponent(isHighlighted ? 0.82 : 1).setFill()
                shape.fill()
                foreground = contrastText(on: accent)
            case .tinted:
                accent.withAlphaComponent(isHighlighted ? 0.22 : 0.12).setFill()
                shape.fill()
                foreground = .labelColor
            case .outlined:
                if isHighlighted {
                    NSColor.quaternaryLabelColor.setFill()
                    shape.fill()
                }
                NSColor.separatorColor.setStroke()
                shape.lineWidth = 1
                shape.stroke()
                foreground = .labelColor
            case .plain:
                if isHighlighted {
                    NSColor.quaternaryLabelColor.setFill()
                    shape.fill()
                }
                foreground = .labelColor
            }
        }
        if imagePosition == .imageOnly, let image {
            let symbol = image.withSymbolConfiguration(.init(paletteColors: [foreground])) ?? image
            let side: CGFloat = min(14, min(bounds.width, bounds.height) - 4)
            symbol.draw(in: .init(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side),
                        from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            let font = font ?? .systemFont(ofSize: 13)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foreground, .paragraphStyle: paragraph]
            let height = ceil((title as NSString).size(withAttributes: attributes).height)
            (title as NSString).draw(in: .init(x: 7, y: bounds.midY - height / 2, width: max(0, bounds.width - 14), height: height),
                                    withAttributes: attributes)
        }
    }

    private func contrastText(on background: NSColor) -> NSColor {
        guard let rgb = background.usingColorSpace(.sRGB) else { return .white }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
        return 1.05 / (luminance + 0.05) >= (luminance + 0.05) / 0.05 ? .white : .black
    }
}

/// Reuses native controls while typing; only text and frames change per update.
@MainActor
final class CandidatePanel: NSPanel {
    private let surface = CandidateSurface()
    private let header = NSTextField(labelWithString: "")
    private let preeditField = NSTextField(wrappingLabelWithString: "")
    private let sourceField = NSTextField(wrappingLabelWithString: "")
    private let translatedField = NSTextField(wrappingLabelWithString: "")
    private let statusField = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private var buttons: [CandidateButton] = []
    private let previous = CandidateButton(title: "‹", target: nil, action: nil)
    private let next = CandidateButton(title: "›", target: nil, action: nil)
    private let translationToggle = CandidateButton(title: "中译英  ⌃⇧T", target: nil, action: nil)
    private let settings = CandidateButton(title: "", target: nil, action: nil)
    private let english = CandidateButton(title: "⌃↩ 输入英文", target: nil, action: nil)
    private let chinese = CandidateButton(title: "↩ 输入中文", target: nil, action: nil)
    private var choose: ((Int) -> Void)?
    private var forget: ((Int) -> Void)?
    private var page: ((Bool) -> Void)?
    private var confirm: (() -> Void)?
    private var original: (() -> Void)?
    private var toggleTranslation: (() -> Void)?
    private var openSettings: (() -> Void)?

    init() {
        super.init(contentRect: .init(x: 0, y: 0, width: 420, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        surface.material = .popover
        surface.blendingMode = .behindWindow
        surface.state = .active
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 11
        surface.autoresizingMask = [.width, .height]
        contentView = surface
        for field in [header, preeditField, sourceField, translatedField, statusField, footer] {
            field.isSelectable = false
            field.lineBreakMode = .byWordWrapping
            surface.addSubview(field)
        }
        header.font = .systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        preeditField.font = .systemFont(ofSize: 14)
        preeditField.textColor = .secondaryLabelColor
        sourceField.font = .systemFont(ofSize: 13)
        sourceField.textColor = .secondaryLabelColor
        translatedField.font = .systemFont(ofSize: 16)
        statusField.font = .systemFont(ofSize: 11)
        statusField.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .tertiaryLabelColor
        for index in 0..<7 {
            let button = CandidateButton(title: "", target: self, action: #selector(selectCandidate(_:)))
            button.tag = index
            button.bezelStyle = .inline
            button.cell?.lineBreakMode = .byTruncatingTail
            surface.addSubview(button)
            buttons.append(button)
        }
        for button in [previous, next, translationToggle, settings, english, chinese] {
            button.bezelStyle = .inline
            button.target = self
            surface.addSubview(button)
        }
        previous.action = #selector(previousPage)
        next.action = #selector(nextPage)
        translationToggle.action = #selector(toggleTranslationMode)
        translationToggle.font = .systemFont(ofSize: 11, weight: .medium)
        translationToggle.emphasis = .tinted
        english.emphasis = .accent
        chinese.emphasis = .outlined
        settings.action = #selector(showSettings)
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Monkey 设置")
        settings.imagePosition = .imageOnly
        settings.isBordered = false
        settings.contentTintColor = .secondaryLabelColor
        settings.toolTip = "Monkey 设置 · 账号、钥匙串与翻译偏好"
        settings.setAccessibilityLabel("打开 Monkey 设置")
        english.action = #selector(confirmTranslation)
        chinese.action = #selector(commitChinese)
        previous.setAccessibilityLabel("上一页候选")
        next.setAccessibilityLabel("下一页候选")
        english.setAccessibilityLabel("确认完成的英文翻译，Control Return")
        chinese.setAccessibilityLabel("输入中文草稿，Return")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(preedit: String, candidates: [String], comments: [String], highlighted: Int,
                pageNumber: Int, isLastPage: Bool, literal: Bool, asciiMode: Bool, translationMode: Bool,
                draft: TranslationDraft, message: String?, cursor: NSRect,
                onChoose: @escaping (Int) -> Void, onForget: @escaping (Int) -> Void,
                onPage: @escaping (Bool) -> Void, onConfirm: @escaping () -> Void, onChinese: @escaping () -> Void,
                onToggleTranslation: (() -> Void)? = nil, onOpenSettings: (() -> Void)? = nil) {
        choose = onChoose; forget = onForget; page = onPage; confirm = onConfirm; original = onChinese
        toggleTranslation = onToggleTranslation
        openSettings = onOpenSettings
        let screen = NSScreen.screens.first { $0.frame.contains(cursor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        let compact = TypingPreferences.horizontalCandidates
        let hasTranslationDraft = translationMode && !draft.source.isEmpty
        let width: CGFloat = min(hasTranslationDraft ? 480 : (compact ? 540 : 360), visible.width - 24)
        let available = width - 28
        var y: CGFloat = 10
        let inputInTopBar = !hasTranslationDraft && !preedit.isEmpty
        header.stringValue = inputInTopBar ? preedit : (translationMode ? "中 → 英 · 联网" : (literal ? "原文 · ASCII" : "中文 · 拼音"))
        header.font = .systemFont(ofSize: inputInTopBar ? 14 : 11, weight: .medium)
        header.textColor = inputInTopBar ? .labelColor : .secondaryLabelColor
        let hasPaging = !literal && (pageNumber > 0 || !isLastPage)
        let pagingWidth: CGFloat = hasPaging ? 60 : 0
        let settingsWidth: CGFloat = 26
        let toggleWidth: CGFloat = 124
        header.frame = .init(x: 14, y: y, width: available - settingsWidth - pagingWidth - toggleWidth - 8, height: inputInTopBar ? 20 : 16)
        header.lineBreakMode = .byTruncatingTail
        translationToggle.title = translationMode ? "关闭中译英  ⌃⇧T" : "中译英  ⌃⇧T"
        translationToggle.frame = .init(x: width - 14 - settingsWidth - pagingWidth - toggleWidth, y: y - 3, width: toggleWidth, height: 22)
        translationToggle.isEnabled = onToggleTranslation != nil
        translationToggle.contentTintColor = translationMode ? .secondaryLabelColor : .controlAccentColor
        translationToggle.toolTip = translationMode ? "关闭联网翻译并输入中文草稿（Control Shift T）" : "开启中译英（Control Shift T）；选词组成的中文草稿会发送至 OpenAI"
        translationToggle.setAccessibilityLabel(translationMode ? "关闭中译英，Control Shift T" : "开启中译英，Control Shift T")
        settings.frame = .init(x: width - 36, y: y - 3, width: 22, height: 22)
        settings.isEnabled = onOpenSettings != nil
        previous.frame = .init(x: width - settingsWidth - 65, y: y - 2, width: 22, height: 22)
        next.frame = .init(x: width - settingsWidth - 39, y: y - 2, width: 22, height: 22)
        previous.isHidden = !hasPaging
        next.isHidden = previous.isHidden
        previous.isEnabled = pageNumber > 0
        next.isEnabled = !isLastPage
        header.toolTip = inputInTopBar ? "\(preedit) · \(translationMode ? "中译英已开启" : "本地输入")" : "第 \(pageNumber + 1) 页 · PgUp/PgDn 或 -/= 翻页"
        y += inputInTopBar ? 24 : 21
        place(preeditField, text: inputInTopBar ? "" : preedit, width: available, y: &y, lines: 2)
        var x: CGFloat = 14
        let rowHeight: CGFloat = 28
        var hasButtons = false
        for (index, button) in buttons.enumerated() {
            guard candidates.indices.contains(index) else { button.isHidden = true; continue }
            hasButtons = true
            button.isHidden = false
            let candidate = candidates[index]
            let hint = comments.indices.contains(index) ? comments[index] : ""
            button.title = literal ? "\(hint.isEmpty ? "原文" : hint)  \(candidate)" : "\(index + 1)  \(candidate)"
            button.font = .systemFont(ofSize: 17, weight: index == highlighted ? .semibold : .regular)
            button.emphasis = index == highlighted ? .accent : .plain
            button.toolTip = hint.isEmpty ? candidate : "\(candidate) · \(hint)"
            button.setAccessibilityLabel(literal ? "\(hint)：\(candidate)" : "候选 \(index + 1)：\(candidate)")
            let measured = ceil((button.title as NSString).size(withAttributes: [.font: button.font!]).width) + 24
            let buttonWidth = compact ? min(measured, available) : available
            if compact && x > 14 && x + buttonWidth > width - 14 { x = 14; y += rowHeight }
            button.frame = .init(x: x, y: y, width: buttonWidth, height: rowHeight)
            if compact { x += buttonWidth + 5 } else { y += rowHeight }
            if literal || hint == "英文" || hint == "中英混输" { button.menu = nil }
            else {
                let menu = NSMenu()
                let item = NSMenuItem(title: "删除该词的个人学习记录", action: #selector(forgetCandidate(_:)), keyEquivalent: "")
                item.target = self; item.tag = index
                menu.addItem(item)
                button.menu = menu
            }
        }
        if hasButtons && compact { y += rowHeight }
        if hasTranslationDraft {
            y += 5
            place(sourceField, text: draft.source, width: available, y: &y, lines: 3)
            place(translatedField, text: draft.translation, width: available, y: &y, lines: 6)
            let status: String
            switch draft.status {
            case .idle: status = "照常选词后预览英文 · 回车输入中文，⌃↩ 输入英文"
            case .waiting: status = "等待选词完成后翻译 · 回车可直接输入中文"
            case .translating: status = "正在翻译…"
            case .ready: status = "译文已就绪 · 回车输入中文，⌃↩ 输入英文"
            case .failed(let error): status = error
            }
            place(statusField, text: message ?? status, width: available, y: &y, lines: 3)
            english.isHidden = false; chinese.isHidden = false
            english.isEnabled = draft.canConfirm && preedit.isEmpty
            chinese.isEnabled = !draft.source.isEmpty || !preedit.isEmpty
            english.frame = .init(x: 14, y: y, width: 150, height: 25)
            chinese.frame = .init(x: 176, y: y, width: 150, height: 25)
            y += 29
            footer.isHidden = true
        } else {
            sourceField.isHidden = true; translatedField.isHidden = true
            english.isHidden = true; chinese.isHidden = true
            place(statusField, text: message ?? "", width: available, y: &y, lines: 2)
            footer.isHidden = false
            let wordWithoutSpace = literal && MixedInputPolicy.classify(preedit) == .english && !TypingPreferences.englishSpaceInsertsSpace
            if translationMode {
                footer.stringValue = "空格 选词后预览英文 · ↩ 中文 · ⌃↩ 英文"
            } else {
                footer.stringValue = literal ? (wordWithoutSpace ? "空格 选英文 · ↩ 原文 · Esc 取消" : "空格 确认并分隔 · ↩ 原文 · Esc 取消") : "空格 选词 · ↩ 原文 · PgUp/PgDn 翻页"
            }
            footer.frame = .init(x: 14, y: y + 2, width: available, height: 16)
            y += 21
        }
        let size = NSSize(width: width, height: y + 10)
        var origin = NSPoint(x: cursor.minX, y: cursor.minY - size.height - 5)
        if cursor == .zero { origin = .init(x: visible.midX - size.width / 2, y: visible.midY) }
        if origin.y < visible.minY { origin.y = min(cursor.maxY + 5, visible.maxY - size.height) }
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        setFrame(.init(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }

    private func place(_ field: NSTextField, text: String, width: CGFloat, y: inout CGFloat, lines: Int) {
        field.isHidden = text.isEmpty
        guard !text.isEmpty else { return }
        field.stringValue = text
        field.maximumNumberOfLines = lines
        let font = field.font ?? .systemFont(ofSize: 13)
        let bounds = (text as NSString).boundingRect(with: .init(width: width, height: .greatestFiniteMagnitude),
                                                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let height = min(ceil(bounds.height) + 3, ceil(font.boundingRectForFont.height) * CGFloat(lines))
        field.frame = .init(x: 14, y: y, width: width, height: max(height, 17))
        y += max(height, 17) + 5
    }

    @objc private func selectCandidate(_ sender: NSButton) { choose?(sender.tag) }
    @objc private func forgetCandidate(_ sender: NSMenuItem) { forget?(sender.tag) }
    @objc private func previousPage() { page?(true) }
    @objc private func nextPage() { page?(false) }
    @objc private func toggleTranslationMode() { toggleTranslation?() }
    @objc private func showSettings() { openSettings?() }
    @objc private func confirmTranslation() { confirm?() }
    @objc private func commitChinese() { original?() }
}
