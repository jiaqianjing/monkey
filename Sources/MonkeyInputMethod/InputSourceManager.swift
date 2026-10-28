import AppKit
import Carbon
import Foundation

enum InputSourceManager {
    static let bundleID = "org.monkey.inputmethod.Monkey"
    static let modeID = "org.monkey.inputmethod.Monkey.Hans"

    static func runCommand(_ args: [String]) -> Int32? {
        if args.contains("--quit") {
            DistributedNotificationCenter.default().postNotificationName(.init("org.monkey.inputmethod.terminate"), object: nil, userInfo: nil, deliverImmediately: true)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
            return 0
        }
        if args.contains("--register") {
            let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
            print("TISRegisterInputSource: \(status)")
            return status == noErr ? 0 : 1
        }
        if args.contains("--list-input-sources") {
            let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            for source in sources() {
                let id = string(source, kTISPropertyInputSourceID)
                let name = string(source, kTISPropertyLocalizedName)
                let selected = string(current, kTISPropertyInputSourceID) == id ? "*" : " "
                print("\(selected) \(id)\t\(name)")
            }
            return 0
        }
        for (flag, operation) in [
            ("--enable", TISEnableInputSource),
            ("--disable", TISDisableInputSource),
            ("--select", TISSelectInputSource)
        ] {
            guard let index = args.firstIndex(of: flag) else { continue }
            let requestedID = args.indices.contains(index + 1) && !args[index + 1].hasPrefix("--") ? args[index + 1] : modeID
            let matching = sources().filter { string($0, kTISPropertyInputSourceID) == requestedID }
            guard !matching.isEmpty else {
                fputs("未找到输入源 \(requestedID)。首次安装后可能需要注销并重新登录。\n", stderr)
                return 1
            }
            let statuses = matching.map { operation($0) }
            print("\(flag): \(statuses)")
            return statuses.contains(noErr) ? 0 : 1
        }
        return nil
    }

    private static func sources() -> [TISInputSource] {
        TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
    }

    private static func string(_ source: TISInputSource, _ key: CFString) -> String {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
