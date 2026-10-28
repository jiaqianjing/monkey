import AppKit
import MonkeyCore

@MainActor
final class CandidatePanel: NSPanel {
    private var choose: ((Int) -> Void)?
    private var confirm: (() -> Void)?
    private var chinese: (() -> Void)?

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
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(preedit: String, candidates: [String], highlighted: Int, asciiMode: Bool, translationMode: Bool,
                draft: TranslationDraft, message: String?, cursor: NSRect,
                onChoose: @escaping (Int) -> Void, onConfirm: @escaping () -> Void, onChinese: @escaping () -> Void) {
        choose = onChoose
        confirm = onConfirm
        chinese = onChinese
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effect.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -12),
            effect.widthAnchor.constraint(equalToConstant: translationMode ? 440 : 340)
        ])
        let header = label(translationMode ? "Monkey   中 → 英 · \(asciiMode ? "英文直输" : "拼音") · 联网翻译" : "Monkey \(asciiMode ? "英文" : "拼音")", size: 11, color: .secondaryLabelColor)
        stack.addArrangedSubview(header)
        if !preedit.isEmpty { stack.addArrangedSubview(label(preedit, size: 14, color: .secondaryLabelColor)) }
        for (index, candidate) in candidates.prefix(7).enumerated() {
            let button = NSButton(title: "\(index + 1)   \(candidate)", target: self, action: #selector(selectCandidate(_:)))
            button.tag = index
            button.bezelStyle = .inline
            button.isBordered = index == highlighted
            button.font = .systemFont(ofSize: 17, weight: index == highlighted ? .semibold : .regular)
            button.contentTintColor = index == highlighted ? .controlAccentColor : .labelColor
            button.setAccessibilityLabel("候选 \(index + 1)：\(candidate)")
            stack.addArrangedSubview(button)
        }
        if translationMode {
            if !draft.source.isEmpty {
                let line = label(draft.source, size: 13, color: .secondaryLabelColor)
                line.maximumNumberOfLines = 3
                stack.addArrangedSubview(line)
            }
            if !draft.translation.isEmpty {
                let translated = label(draft.translation, size: 16, color: .labelColor)
                translated.maximumNumberOfLines = 6
                stack.addArrangedSubview(translated)
            }
            let status: String
            switch draft.status {
            case .idle: status = "照常拼音选词，英文将在这里预览"
            case .waiting: status = "等待本句输入…"
            case .translating: status = "正在翻译…"
            case .ready: status = "译文已就绪"
            case .failed(let error): status = error
            }
            let statusLabel = label(message ?? status, size: 11, color: .secondaryLabelColor)
            statusLabel.maximumNumberOfLines = 3
            stack.addArrangedSubview(statusLabel)
            let actions = NSStackView()
            actions.orientation = .horizontal
            actions.spacing = 12
            let english = NSButton(title: "⌃↩ 输入英文", target: self, action: #selector(confirmTranslation))
            english.bezelStyle = .inline
            english.isEnabled = draft.canConfirm && preedit.isEmpty
            let original = NSButton(title: "⇧↩ 输入中文", target: self, action: #selector(commitChinese))
            original.bezelStyle = .inline
            original.isEnabled = !draft.source.isEmpty || !preedit.isEmpty
            actions.addArrangedSubview(english)
            actions.addArrangedSubview(original)
            stack.addArrangedSubview(actions)
        } else if let message {
            stack.addArrangedSubview(label(message, size: 11, color: .secondaryLabelColor))
        }
        contentView = effect
        effect.layoutSubtreeIfNeeded()
        let size = effect.fittingSize
        let screen = NSScreen.screens.first { $0.frame.contains(cursor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        var origin = NSPoint(x: cursor.minX, y: cursor.minY - size.height - 5)
        if cursor == .zero { origin = .init(x: visible.midX - size.width / 2, y: visible.midY) }
        if origin.y < visible.minY { origin.y = min(cursor.maxY + 5, visible.maxY - size.height) }
        origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
        origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        setFrame(.init(origin: origin, size: size), display: true)
        orderFrontRegardless()
    }

    private func label(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size)
        field.textColor = color
        field.isSelectable = false
        field.maximumNumberOfLines = 2
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    @objc private func selectCandidate(_ sender: NSButton) { choose?(sender.tag) }
    @objc private func confirmTranslation() { confirm?() }
    @objc private func commitChinese() { chinese?() }
}
