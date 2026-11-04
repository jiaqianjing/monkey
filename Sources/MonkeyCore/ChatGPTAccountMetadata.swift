import CoreFoundation
import Darwin
import Foundation

/// Cross-process serialization for the short, synchronous UserDefaults metadata
/// transactions. Never acquire a credential refresh lock while holding this lock;
/// operations that need both acquire the per-client lock first.
enum ChatGPTAccountMetadata {
    static func withLock<T>(defaults: UserDefaults, directory: URL? = nil, domain: String = "org.monkey.inputmethod.shared", _ body: () throws -> T) throws -> T {
        let directory = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Monkey", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(directory.appendingPathComponent("accounts.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw ChatGPTError.message("无法安全锁定 ChatGPT 连接信息。") }
        defer { Darwin.close(fd) }
        // Do not let a suspended process hold the input-method main thread
        // indefinitely. No protected state is used if acquisition times out.
        var acquired = false
        for _ in 0..<50 {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { acquired = true; break }
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw ChatGPTError.message("无法锁定 ChatGPT 连接信息。") }
            usleep(5_000)
        }
        guard acquired else { throw ChatGPTError.message("另一处 Monkey 正在更新连接，请稍后重试。") }
        defer { flock(fd, LOCK_UN) }
        // CFPreferences caches across processes; refresh inside the lock and
        // flush before releasing it so the next transaction sees this update.
        guard CFPreferencesAppSynchronize(domain as CFString) else { throw ChatGPTError.message("无法读取 ChatGPT 连接信息。") }
        let result = try body()
        guard defaults.synchronize(), CFPreferencesAppSynchronize(domain as CFString) else {
            throw ChatGPTError.message("无法保存 ChatGPT 连接信息。")
        }
        return result
    }

    static func accounts(_ defaults: UserDefaults) throws -> [ChatGPTAccount] {
        guard let data = defaults.data(forKey: "ChatGPT.accounts") else { return [] }
        return try JSONDecoder().decode([ChatGPTAccount].self, from: data)
    }

    static func setDisabled(_ id: String, disabled: Bool, defaults: UserDefaults) {
        var values = (defaults.stringArray(forKey: "ChatGPT.disabledClients") ?? []).filter { $0 != id }
        if disabled { values.append(id) }
        defaults.set(values, forKey: "ChatGPT.disabledClients")
    }
}
