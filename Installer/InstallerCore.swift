import AppKit
import CryptoKit
import Darwin
import Foundation
import Security

enum InstallerFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct InstalledApp {
    let version: String
    let build: String
    let minimumOS: String

    static let bundleID = "org.monkey.inputmethod.Monkey"
    static let executableName = "MonkeyInputMethod"

    static func read(at app: URL) throws -> InstalledApp {
        try PathSafety.rejectSymlink(app)
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let data = try Data(contentsOf: plist)
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == bundleID,
              info["CFBundleExecutable"] as? String == executableName,
              info["CFBundlePackageType"] as? String == "APPL",
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else {
            throw InstallerFailure.message("这个位置不是有效的 Monkey 输入法，已停止安装。")
        }
        try PathSafety.rejectSymlink(app.appendingPathComponent("Contents"))
        try PathSafety.rejectSymlink(plist)
        let executable = app.appendingPathComponent("Contents/MacOS/\(executableName)")
        try PathSafety.rejectSymlink(app.appendingPathComponent("Contents/MacOS"))
        try PathSafety.rejectSymlink(executable)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw InstallerFailure.message("Monkey 主程序不完整，已停止安装。")
        }
        return InstalledApp(version: version, build: build, minimumOS: info["LSMinimumSystemVersion"] as? String ?? "13.0")
    }
}

struct InstallerConfiguration {
    static let bundleID = "org.monkey.inputmethod.Installer"
    let archive: URL
    let archiveSHA256: String
    let teamID: String
    let version: String
    let build: String
    let development: Bool

    static func load() throws -> InstallerConfiguration {
        let bundle = Bundle.main
        guard bundle.bundleIdentifier == bundleID,
              let archive = bundle.url(forResource: "MonkeyPayload", withExtension: "zip"),
              let hash = bundle.object(forInfoDictionaryKey: "MonkeyPayloadSHA256") as? String,
              let version = bundle.object(forInfoDictionaryKey: "MonkeyPayloadVersion") as? String,
              let build = bundle.object(forInfoDictionaryKey: "MonkeyPayloadBuild") as? String else {
            throw InstallerFailure.message("安装器资源不完整。请重新下载完整发行包。")
        }
        return InstallerConfiguration(archive: archive, archiveSHA256: hash,
            teamID: bundle.object(forInfoDictionaryKey: "MonkeyPayloadTeamIdentifier") as? String ?? "",
            version: version, build: build,
            development: bundle.object(forInfoDictionaryKey: "MonkeyInstallerDevelopmentMode") as? Bool ?? false)
    }

    func verifyEnvelope() throws {
        let verifier = SignatureVerifier(teamID: teamID, development: development)
        try verifier.verifyCode(at: Bundle.main.bundleURL, identifier: Self.bundleID)
        try PathSafety.rejectSymlink(archive)
        let actual = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        guard actual == archiveSHA256 else {
            throw InstallerFailure.message("安装资源校验失败，未更改现有输入法。请重新下载发行包。")
        }
    }
}

struct SignatureVerifier {
    let teamID: String
    let development: Bool

    func verifyCode(at app: URL, identifier: String) throws {
        var code: SecStaticCode?
        let creation = SecStaticCodeCreateWithPath(app as CFURL, SecCSFlags(), &code)
        guard creation == errSecSuccess, let code else { throw failure("无法读取应用签名", creation) }
        var requirement: SecRequirement?
        var expression = "identifier \"\(identifier)\""
        if !development {
            guard teamID.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil else {
                throw InstallerFailure.message("安装器没有有效的开发者团队信息。")
            }
            expression += " and anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"\(teamID)\""
        }
        let parsed = SecRequirementCreateWithString(expression as CFString, SecCSFlags(), &requirement)
        guard parsed == errSecSuccess else { throw failure("无法校验开发者身份", parsed) }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        guard status == errSecSuccess else { throw failure("应用签名或开发者身份不匹配", status) }
        if !development {
            var information: CFDictionary?
            let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
            guard status == errSecSuccess,
                  let info = information as? [String: Any],
                  info[kSecCodeInfoTeamIdentifier as String] as? String == teamID else {
                throw InstallerFailure.message("Monkey 与安装器的开发者团队不一致，已停止安装。")
            }
        }
    }

    func verifyApp(at app: URL) throws -> InstalledApp {
        let information = try InstalledApp.read(at: app)
        try verifyCode(at: app, identifier: InstalledApp.bundleID)
        // The build pipeline verifies and embeds the payload's stapled ticket.
        // Do not invoke stapler/spctl or require network access on the user's Mac.
        // macOS applies its ordinary Gatekeeper policy when the signed app runs.
        return information
    }

    private func failure(_ message: String, _ status: OSStatus) -> InstallerFailure {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "错误 \(status)"
        return .message("\(message)：\(detail)。未运行待安装的程序。")
    }
}

struct CommandResult {
    let status: Int32
    let output: String
}

enum CommandRunner {
    static func run(executable: URL, arguments: [String], timeout: TimeInterval = 15) throws -> CommandResult {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyInstaller-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: log) }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.025) }
        if process.isRunning {
            process.terminate()
            let grace = Date().addingTimeInterval(1)
            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.025) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw InstallerFailure.message("安装步骤等待超时，已停止本次操作。请退出 Monkey 设置后重试。")
        }
        process.waitUntilExit()
        try output.synchronize()
        let data = try Data(contentsOf: log)
        guard data.count <= 1_048_576 else { throw InstallerFailure.message("安装命令返回的数据异常，已停止操作。") }
        return CommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    static func app(_ app: URL, arguments: [String]) throws -> CommandResult {
        try run(executable: app.appendingPathComponent("Contents/MacOS/\(InstalledApp.executableName)"), arguments: arguments)
    }
}

enum PathSafety {
    static func exists(_ url: URL) -> Bool {
        var value = stat()
        return lstat(url.path, &value) == 0
    }

    static func rejectSymlink(_ url: URL) throws {
        var value = stat()
        guard lstat(url.path, &value) == 0 else {
            throw InstallerFailure.message("安装路径不存在或无法读取：\(url.path)")
        }
        guard value.st_mode & S_IFMT != S_IFLNK else {
            throw InstallerFailure.message("安装路径包含符号链接，已停止以保护原文件：\(url.path)")
        }
    }

    static func currentUserInputMethods() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        let library = home.appendingPathComponent("Library", isDirectory: true)
        try rejectSymlink(library)
        let parent = library.appendingPathComponent("Input Methods", isDirectory: true)
        if exists(parent) { try rejectSymlink(parent) }
        return parent
    }

    static func fileID(_ url: URL) -> String? {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return nil }
        return "\(value.st_dev):\(value.st_ino)"
    }
}

final class InstallLock {
    private var descriptor: Int32 = -1
    init(parent: URL) throws {
        let path = parent.appendingPathComponent(".monkey-installer.lock")
        let opened = open(path.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard opened >= 0 else { throw InstallerFailure.message("无法创建安装锁，请检查当前账户的输入法目录权限。") }
        var value = stat()
        guard fstat(opened, &value) == 0, value.st_uid == getuid(),
              value.st_mode & S_IFMT == S_IFREG else {
            close(opened)
            throw InstallerFailure.message("安装锁文件不属于当前用户，已停止安装。")
        }
        guard flock(opened, LOCK_EX | LOCK_NB) == 0 else {
            close(opened)
            throw InstallerFailure.message("另一个 Monkey 安装器正在运行，请等待其完成。")
        }
        descriptor = opened
    }
    deinit { if descriptor >= 0 { flock(descriptor, LOCK_UN); close(descriptor) } }
}

struct InstallOutcome {
    let target: URL
    let information: InstalledApp
    let registrationFinished: Bool
}

/// Only this transaction mutates an installation. Production supplies the
/// current user's fixed Input Methods directory. --self-test supplies a newly
/// created disposable directory and fake verification/commands; no CLI accepts
/// an arbitrary install destination or a verification-bypass switch.
final class InstallTransaction {
    let parent: URL
    let prepare: (URL) throws -> URL
    let verify: (URL) throws -> InstalledApp
    let command: (URL, [String]) throws -> CommandResult
    let ensureStopped: (URL) throws -> Void

    init(parent: URL, prepare: @escaping (URL) throws -> URL,
         verify: @escaping (URL) throws -> InstalledApp,
         command: @escaping (URL, [String]) throws -> CommandResult,
         ensureStopped: @escaping (URL) throws -> Void = { _ in }) {
        self.parent = parent; self.prepare = prepare; self.verify = verify
        self.command = command; self.ensureStopped = ensureStopped
    }

    func install(progress: (String) -> Void = { _ in }) throws -> InstallOutcome {
        let manager = FileManager.default
        if PathSafety.exists(parent) {
            try PathSafety.rejectSymlink(parent)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw InstallerFailure.message("输入法安装位置不是文件夹，已停止安装。")
            }
        } else { try manager.createDirectory(at: parent, withIntermediateDirectories: false) }
        let lock = try InstallLock(parent: parent)
        defer { withExtendedLifetime(lock) {} }
        let target = parent.appendingPathComponent("Monkey.app", isDirectory: true)
        let previous = PathSafety.exists(target) ? try InstalledApp.read(at: target) : nil
        let previousFileID = previous == nil ? nil : PathSafety.fileID(target)
        let stage = parent.appendingPathComponent(".MonkeyInstall-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var cleanStage = true
        defer { if cleanStage { try? manager.removeItem(at: stage) } }
        let backup = stage.appendingPathComponent("PreviousMonkey.app", isDirectory: true)
        var previousMoved = false
        var newMoved = false
        var installedFileID: String?
        do {
            progress("正在验证安装资源…")
            let incoming = try prepare(stage)
            let information = try verify(incoming)
            guard incoming.standardizedFileURL.path == stage.appendingPathComponent("Monkey.app").standardizedFileURL.path else {
                throw InstallerFailure.message("安装资源路径不正确。")
            }
            if let previous {
                let comparison = information.version.compare(previous.version, options: .numeric)
                if comparison == .orderedAscending {
                    throw InstallerFailure.message("已安装版本 \(previous.version) 高于安装包 \(information.version)，本次未替换。")
                }
                if comparison == .orderedSame && information.build.compare(previous.build, options: .numeric) == .orderedAscending {
                    throw InstallerFailure.message("已安装 \(previous.version) 的构建 \(previous.build) 更新，本次不降级到构建 \(information.build)。")
                }
            }
            let currentOS = ProcessInfo.processInfo.operatingSystemVersion
            let osVersion = "\(currentOS.majorVersion).\(currentOS.minorVersion).\(currentOS.patchVersion)"
            guard osVersion.compare(information.minimumOS, options: .numeric) != .orderedAscending else {
                throw InstallerFailure.message("此版本需要 macOS \(information.minimumOS) 或更新版本。")
            }
            if previous != nil {
                guard previousFileID != nil, PathSafety.fileID(target) == previousFileID else {
                    throw InstallerFailure.message("已安装的程序在验证期间被其他操作更改，未替换它。请重试。")
                }
                _ = try InstalledApp.read(at: target)
                progress("正在结束旧版 Monkey…")
                // NSRunningApplication targets only this exact installed path.
                // Never execute an old app or broadcast the app's global --quit.
                try ensureStopped(target)
                try PathSafety.rejectSymlink(target)
                guard PathSafety.fileID(target) == previousFileID else {
                    throw InstallerFailure.message("已安装的程序在退出等待期间被其他操作更改，未替换它。请重试。")
                }
                _ = try InstalledApp.read(at: target)
                try manager.moveItem(at: target, to: backup)
                previousMoved = true
            } else if PathSafety.exists(target) {
                throw InstallerFailure.message("安装位置刚被其他操作创建，本次未替换它。请重试。")
            }
            progress("正在安装 Monkey \(information.version)…")
            try manager.moveItem(at: incoming, to: target)
            newMoved = true
            installedFileID = PathSafety.fileID(target)
            _ = try verify(target)
            progress("正在注册输入法…")
            let registered = try command(target, ["--register"])
            let enabled = try command(target, ["--enable"])
            // Nonzero Text Input Source status can simply require a new login
            // session. A valid installed app is kept and the UI says so clearly.
            return InstallOutcome(target: target, information: information,
                registrationFinished: registered.status == 0 && enabled.status == 0)
        } catch {
            do {
                if newMoved {
                    // Do not replace resources beneath a version that refused
                    // to exit. Preserve both it and the backup for recovery.
                    try ensureStopped(target)
                }
                if newMoved, PathSafety.exists(target) {
                    guard installedFileID != nil, PathSafety.fileID(target) == installedFileID else {
                        throw InstallerFailure.message("安装位置在操作期间被其他程序改动，未删除该位置的内容。")
                    }
                    try manager.removeItem(at: target)
                }
                if previousMoved { try manager.moveItem(at: backup, to: target) }
            } catch let rollbackError {
                cleanStage = false
                let retained = previousMoved ? "旧版备份保留在：\(backup.path)" : "待处理资源保留在：\(stage.path)"
                throw InstallerFailure.message("安装未完成，自动恢复也未完成：\(rollbackError.localizedDescription)\n\(retained)\n请保留这些文件并联系支持。")
            }
            throw error
        }
    }
}

enum PayloadPreparation {
    static func extract(_ configuration: InstallerConfiguration, to stage: URL) throws -> URL {
        try configuration.verifyEnvelope()
        let listing = try CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/zipinfo"),
            arguments: ["-1", configuration.archive.path])
        guard listing.status == 0 else { throw InstallerFailure.message("无法读取安装资源。") }
        for name in listing.output.split(separator: "\n") {
            let parts = name.split(separator: "/", omittingEmptySubsequences: false)
            guard !name.hasPrefix("/"), !parts.contains(".."),
                  parts.first == "Monkey.app" || parts.first == "__MACOSX" else {
                throw InstallerFailure.message("安装压缩包包含无效路径，已停止安装。")
            }
        }
        let extracted = try CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", configuration.archive.path, stage.path], timeout: 60)
        guard extracted.status == 0 else { throw InstallerFailure.message("安装资源无法解压，现有输入法没有被替换。") }
        return stage.appendingPathComponent("Monkey.app", isDirectory: true)
    }
}
