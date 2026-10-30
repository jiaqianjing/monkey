import AppKit
import Foundation

@main
enum MonkeyInstallerMain {
    static func main() {
        do {
            if CommandLine.arguments.contains("--self-test") { try InstallerSelfTest.run(); return }
            let configuration = try InstallerConfiguration.load()
            if CommandLine.arguments.contains("--verify-payload") {
                try configuration.verifyEnvelope()
                let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyPayloadCheck-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                defer { try? FileManager.default.removeItem(at: temporary) }
                let payload = try PayloadPreparation.extract(configuration, to: temporary)
                let info = try SignatureVerifier(teamID: configuration.teamID, development: configuration.development).verifyApp(at: payload)
                print("Payload signature, bundle ID and archive hash verified: Monkey \(info.version) (\(info.build)).")
                print(configuration.development ? "Development preview; this build cannot install." : "Developer ID team: \(configuration.teamID). No installation performed.")
                return
            }
            let application = NSApplication.shared
            let delegate = InstallerApplication(configuration: configuration)
            application.delegate = delegate
            application.setActivationPolicy(.regular)
            withExtendedLifetime(delegate) { application.run() }
        } catch {
            fputs("Monkey Installer: \(error.localizedDescription)\n", stderr)
            if !CommandLine.arguments.contains("--verify-payload") && !CommandLine.arguments.contains("--self-test") {
                let application = NSApplication.shared
                application.setActivationPolicy(.regular)
                let alert = NSAlert()
                alert.messageText = "无法打开 Monkey 安装器"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
            exit(1)
        }
    }
}

final class InstallerApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let configuration: InstallerConfiguration
    private var window: NSWindow!
    private let status = NSTextField(wrappingLabelWithString: "正在验证安装资源…")
    private let versions = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let install = NSButton(title: "安装", target: nil, action: nil)
    private let keyboardSettings = NSButton(title: "打开键盘设置", target: nil, action: nil)
    private let monkeySettings = NSButton(title: "打开 Monkey 设置", target: nil, action: nil)
    private var isInstalling = false
    private var installedURL: URL?

    init(configuration: InstallerConfiguration) { self.configuration = configuration }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 580),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Monkey 安装器"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let content = NSView()
        window.contentView = content
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -26)
        ])
        let title = NSTextField(labelWithString: "安装 Monkey 拼音")
        title.font = .systemFont(ofSize: 25, weight: .semibold)
        stack.addArrangedSubview(title)
        versions.font = .systemFont(ofSize: 13)
        versions.textColor = .secondaryLabelColor
        versions.stringValue = "安装包版本 \(configuration.version) (\(configuration.build))"
        stack.addArrangedSubview(versions)
        let explanation = NSTextField(wrappingLabelWithString:
            "仅安装到当前账户的 ~/Library/Input Methods/Monkey.app。更新会先结束旧版 Monkey，个人词库、设置和 ChatGPT 登录信息会保留。")
        explanation.font = .systemFont(ofSize: 14)
        stack.addArrangedSubview(explanation)
        let instruction = NSTextField(wrappingLabelWithString: "安装前请先完成当前输入，并退出 Monkey 设置窗口。安装完成后，从菜单栏输入法菜单选择「Monkey 拼音」。")
        instruction.font = .systemFont(ofSize: 13)
        instruction.textColor = .secondaryLabelColor
        stack.addArrangedSubview(instruction)
        if configuration.development {
            let development = NSTextField(wrappingLabelWithString: "开发预览 · 尚未通过 Apple 公证\n此构建仅用于界面和资源验证，不能执行安装。")
            development.textColor = .systemOrange
            development.font = .systemFont(ofSize: 13, weight: .medium)
            stack.addArrangedSubview(development)
        }
        progress.style = .bar
        progress.isIndeterminate = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 540).isActive = true
        stack.addArrangedSubview(progress)
        status.maximumNumberOfLines = 6
        status.font = .systemFont(ofSize: 13)
        stack.addArrangedSubview(status)
        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.spacing = 12
        install.bezelStyle = .rounded
        install.keyEquivalent = "\r"
        install.target = self
        install.action = #selector(beginInstall)
        install.isEnabled = false
        keyboardSettings.bezelStyle = .rounded
        keyboardSettings.target = self
        keyboardSettings.action = #selector(openKeyboardSettings)
        keyboardSettings.isHidden = true
        monkeySettings.bezelStyle = .rounded
        monkeySettings.target = self
        monkeySettings.action = #selector(openMonkeySettings)
        monkeySettings.isHidden = true
        actions.addArrangedSubview(install)
        actions.addArrangedSubview(monkeySettings)
        actions.addArrangedSubview(keyboardSettings)
        stack.addArrangedSubview(actions)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        progress.startAnimation(nil)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                try configuration.verifyEnvelope()
                let parent = try PathSafety.currentUserInputMethods()
                let target = parent.appendingPathComponent("Monkey.app")
                let previous = PathSafety.exists(target) ? try InstalledApp.read(at: target) : nil
                DispatchQueue.main.async { [self] in
                    progress.stopAnimation(nil)
                    progress.isHidden = true
                    versions.stringValue = "安装包 \(configuration.version) (\(configuration.build))" +
                        (previous.map { "    ·    当前已安装 \($0.version) (\($0.build))" } ?? "    ·    尚未安装")
                    status.stringValue = configuration.development ? "资源校验通过。这是开发预览，安装功能已禁用。" : "资源校验通过。点击「安装」开始。"
                    install.isEnabled = !configuration.development
                }
            } catch { DispatchQueue.main.async { [self] in showError(error) } }
        }
    }

    @objc private func beginInstall() {
        guard !isInstalling, !configuration.development else { return }
        isInstalling = true
        install.isEnabled = false
        progress.isHidden = false
        progress.startAnimation(nil)
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            do {
                let parent = try PathSafety.currentUserInputMethods()
                let verifier = SignatureVerifier(teamID: configuration.teamID, development: false)
                let transaction = InstallTransaction(parent: parent,
                    prepare: { try PayloadPreparation.extract(self.configuration, to: $0) },
                    verify: { try verifier.verifyApp(at: $0) },
                    command: { try CommandRunner.app($0, arguments: $1) },
                    ensureStopped: Self.stopInstalledAppAndWait)
                let outcome = try transaction.install { text in
                    DispatchQueue.main.async { self.status.stringValue = text }
                }
                DispatchQueue.main.async { [self] in
                    isInstalling = false
                    installedURL = outcome.target
                    progress.stopAnimation(nil)
                    progress.isHidden = true
                    install.isHidden = true
                    keyboardSettings.isHidden = false
                    monkeySettings.isHidden = false
                    status.stringValue = outcome.registrationFinished
                        ? "Monkey \(outcome.information.version) 已安装并完成注册。请从菜单栏输入法菜单选择「Monkey 拼音」。若未出现或无法打字，请注销并重新登录后，在键盘设置中添加。"
                        : "Monkey \(outcome.information.version) 已安装。macOS 尚未完成当前登录会话的注册，请注销并重新登录，再在键盘设置 → 文本输入 → 编辑中添加「Monkey 拼音」。"
                }
            } catch { DispatchQueue.main.async { [self] in isInstalling = false; showError(error) } }
        }
    }

    private static func stopInstalledAppAndWait(at target: URL) throws {
        let targetPath = target.standardizedFileURL.path
        DispatchQueue.main.sync {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: InstalledApp.bundleID)
                where app.bundleURL?.standardizedFileURL.path == targetPath && !app.isTerminated {
                _ = app.terminate()
            }
        }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let stillRunning = DispatchQueue.main.sync {
                NSRunningApplication.runningApplications(withBundleIdentifier: InstalledApp.bundleID).contains {
                    $0.bundleURL?.standardizedFileURL.path == targetPath && !$0.isTerminated
                }
            }
            if !stillRunning { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw InstallerFailure.message("旧版 Monkey 仍在运行，未替换现有程序。请完成输入并退出 Monkey 设置后重试。")
    }

    private func showError(_ error: Error) {
        progress.stopAnimation(nil)
        progress.isHidden = true
        status.stringValue = error.localizedDescription
        install.isEnabled = !configuration.development
    }

    @objc private func openKeyboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openMonkeySettings() {
        guard let installedURL else { return }
        let options = NSWorkspace.OpenConfiguration()
        options.arguments = ["--settings"]
        options.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: installedURL, configuration: options)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isInstalling ? .terminateCancel : .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !isInstalling }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
