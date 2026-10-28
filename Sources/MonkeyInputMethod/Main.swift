import AppKit
import Carbon
import InputMethodKit
import MonkeyCore
import MonkeyPinyin
import MonkeySettings
import SwiftUI

@main
struct MonkeyMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if let code = InputSourceManager.runCommand(arguments) { exit(code) }
        if Bundle.main.bundleIdentifier == InputSourceManager.bundleID,
           !arguments.contains("--demo"),
           NSRunningApplication.runningApplications(withBundleIdentifier: InputSourceManager.bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
            if arguments.contains("--settings") {
                DistributedNotificationCenter.default().postNotificationName(.init("org.monkey.inputmethod.showSettings"), object: nil, userInfo: nil, deliverImmediately: true)
            }
            return
        }
        let app = NSApplication.shared
        let delegate = MonkeyApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(arguments.contains("--settings") || arguments.contains("--demo") ? .regular : .accessory)
        delegate.prepareServer()
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class MonkeyApplicationDelegate: NSObject, NSApplicationDelegate {
    private var server: IMKServer?
    private var settingsWindow: NSWindow?
    private var demoWindow: NSWindow?
    private var terminationObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?

    func prepareServer() {
        // Publish the input service before entering the application event loop.
        server = IMKServer(name: "Monkey_Connection", bundleIdentifier: Bundle.main.bundleIdentifier ?? InputSourceManager.bundleID)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminationObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("org.monkey.inputmethod.terminate"), object: nil, queue: .main
        ) { _ in NSApp.terminate(nil) }
        settingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("org.monkey.inputmethod.showSettings"), object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.showSettings() } }
        if CommandLine.arguments.contains("--settings") { showSettings() }
        if CommandLine.arguments.contains("--demo") { showDemo() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func showSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: MonkeySettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "Monkey 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 920, height: 720))
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showDemo() {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 760, height: 450), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Monkey 输入法试用 — 请先在菜单栏选择 Monkey 拼音"
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds)
        text.autoresizingMask = [.width, .height]
        text.font = .systemFont(ofSize: 23)
        text.textContainerInset = .init(width: 24, height: 24)
        text.string = ""
        scroll.documentView = text
        window.contentView = scroll
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        demoWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
enum AppRuntime {
    static var engine: PinyinEngine?
    static var engineError: String?

    static func makeSession() -> PinyinSession? {
        do {
            if engine == nil {
                let shared = Bundle.main.resourceURL!.appendingPathComponent("Rime", isDirectory: true)
                let user = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Monkey/Rime", isDirectory: true)
                try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
                let library = Bundle.main.privateFrameworksURL?.appendingPathComponent("librime.1.dylib")
                engine = try PinyinEngine(sharedDataURL: shared, userDataURL: user, libraryURL: library)
            }
            return try engine?.makeSession()
        } catch {
            engineError = "拼音引擎暂不可用：\(error.localizedDescription)"
            return nil
        }
    }
}
