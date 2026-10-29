import AppKit
import Darwin
import MonkeySettings
import SwiftUI

/// Hosts the production settings view without creating an input-method server.
/// Appearance is scoped to this preview process; no system preference is changed.
@MainActor
enum SettingsPreviewCommand {
    private static var retainedDelegate: SettingsPreviewDelegate?

    static func runIfRequested(_ arguments: [String]) -> Bool {
        guard arguments.contains("--preview-settings") else { return false }
        do {
            let options = try SettingsPreviewOptions(arguments: arguments)
            let app = NSApplication.shared
            let delegate = SettingsPreviewDelegate(options: options)
            retainedDelegate = delegate
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.appearance = NSAppearance(named: options.appearance)
            withExtendedLifetime(delegate) { app.run() }
            delegate.cleanup()
            retainedDelegate = nil
            return true
        } catch {
            fputs("Monkey settings preview: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

private struct SettingsPreviewOptions {
    let appearance: NSAppearance.Name
    let duration: TimeInterval

    init(arguments: [String]) throws {
        let requested = try Self.value("--preview-appearance", in: arguments) ?? "light"
        switch requested.lowercased() {
        case "light": appearance = .aqua
        case "dark": appearance = .darkAqua
        default: throw SettingsPreviewError("--preview-appearance 必须是 light 或 dark。")
        }
        let value = try Self.value("--preview-duration", in: arguments) ?? "120"
        guard let duration = TimeInterval(value), duration > 0, duration <= 3600 else {
            throw SettingsPreviewError("--preview-duration 必须是大于 0 且不超过 3600 的秒数。")
        }
        self.duration = duration
    }

    private static func value(_ name: String, in arguments: [String]) throws -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        guard arguments.indices.contains(index + 1), !arguments[index + 1].hasPrefix("--") else {
            throw SettingsPreviewError("\(name) 缺少参数。")
        }
        return arguments[index + 1]
    }
}

@MainActor
private final class SettingsPreviewDelegate: NSObject, NSApplicationDelegate {
    private let options: SettingsPreviewOptions
    private var window: NSWindow?
    private var durationTimer: Timer?
    private var signalSources: [DispatchSourceSignal] = []

    init(options: SettingsPreviewOptions) { self.options = options }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use the real view and its existing metadata-only initialization.
        // This command does not automatically invoke account, translation, or
        // preference actions; its real controls retain their normal behavior.
        let hosting = NSHostingController(rootView: MonkeySettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Monkey 设置预览"
        window.setAccessibilityLabel("Monkey 设置预览")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.appearance = NSAppearance(named: options.appearance)
        window.setContentSize(NSSize(width: 920, height: 720))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window

        if let icon = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: icon) {
            NSApp.applicationIconImage = image
        }
        installMenu()
        installTerminationSignals()
        durationTimer = Timer.scheduledTimer(withTimeInterval: options.duration, repeats: false) { _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { cleanup() }

    func cleanup() {
        durationTimer?.invalidate()
        durationTimer = nil
        for source in signalSources { source.cancel() }
        signalSources.removeAll()
        window?.orderOut(nil)
        window?.contentViewController = nil
        window = nil
    }

    private func installMenu() {
        let menu = NSMenu()
        let application = NSMenuItem()
        let actions = NSMenu(title: "Monkey 设置预览")
        let quit = NSMenuItem(title: "退出设置预览", action: #selector(quitPreview), keyEquivalent: "q")
        quit.target = self
        actions.addItem(quit)
        application.submenu = actions
        menu.addItem(application)
        NSApp.mainMenu = menu
    }

    private func installTerminationSignals() {
        for identifier in [SIGINT, SIGTERM] {
            Darwin.signal(identifier, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: identifier, queue: .main)
            source.setEventHandler { Task { @MainActor in NSApp.terminate(nil) } }
            source.resume()
            signalSources.append(source)
        }
    }

    @objc private func quitPreview() { NSApp.terminate(nil) }
}

private struct SettingsPreviewError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
