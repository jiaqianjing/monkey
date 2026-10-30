import Foundation

/// Exercises real file moves and recovery using fake application metadata and
/// injected commands. No real app is executed, no notification is sent, and no
/// path under the user's Library/Input Methods is accessed or modified.
enum InstallerSelfTest {
    static func run() throws {
        var passed = 0
        func test(_ name: String, _ body: () throws -> Void) throws {
            try body()
            passed += 1
            print("PASS \(name)")
        }
        try test("fresh install keeps unrelated user data") {
            let fixture = try Fixture(existing: false)
            let outcome = try fixture.transaction().install()
            try require(outcome.registrationFinished, "registration status")
            try require(try fixture.marker() == "new", "new app installed")
            try fixture.assertDataPreserved()
        }
        try test("upgrade replaces only Monkey.app") {
            let fixture = try Fixture()
            let outcome = try fixture.transaction().install()
            try require(outcome.information.version == "0.2.2", "version")
            try require(try fixture.marker() == "new", "replacement")
            try require(fixture.calls == ["--register", "--enable"], "fixed commands")
            try fixture.assertDataPreserved()
        }
        try test("post-move validation failure restores old app") {
            let fixture = try Fixture()
            try expectFailure { _ = try fixture.transaction(failFinalValidation: true).install() }
            try require(try fixture.marker() == "old", "rollback")
            try require(fixture.calls.isEmpty, "unverified installed app was never run")
            try fixture.assertDataPreserved()
        }
        try test("payload preparation failure leaves old app") {
            let fixture = try Fixture()
            try expectFailure { _ = try fixture.transaction(failPreparation: true).install() }
            try require(try fixture.marker() == "old", "old app retained")
            try require(fixture.calls.isEmpty, "no commands")
        }
        try test("old process still running prevents replacement") {
            let fixture = try Fixture()
            try expectFailure { _ = try fixture.transaction(oldStillRunning: true).install() }
            try require(try fixture.marker() == "old", "no replacement")
        }
        try test("command launch failure rolls back") {
            let fixture = try Fixture()
            try expectFailure { _ = try fixture.transaction(failLaunch: true).install() }
            try require(try fixture.marker() == "old", "launch failure rollback")
        }
        try test("registration pending keeps valid installed app") {
            let fixture = try Fixture()
            let outcome = try fixture.transaction(deferRegistration: true).install()
            try require(!outcome.registrationFinished, "accurate pending state")
            try require(try fixture.marker() == "new", "valid installation retained")
        }
        try test("unrelated destination app is not replaced") {
            let fixture = try Fixture()
            try Fixture.writeApp(at: fixture.target, version: "0.2.0", marker: "foreign", identifier: "example.Unrelated")
            try expectFailure { _ = try fixture.transaction().install() }
            try require(try fixture.marker() == "foreign", "foreign app retained")
        }
        try test("symlink destination is not followed") {
            let fixture = try Fixture()
            try FileManager.default.removeItem(at: fixture.target)
            let unrelated = fixture.root.appendingPathComponent("Other.app")
            try Fixture.writeApp(at: unrelated, version: "0.2.0", marker: "other")
            try FileManager.default.createSymbolicLink(at: fixture.target, withDestinationURL: unrelated)
            try expectFailure { _ = try fixture.transaction().install() }
            try require(try String(contentsOf: unrelated.appendingPathComponent("marker")) == "other", "symlink target retained")
            try require(try FileManager.default.destinationOfSymbolicLink(atPath: fixture.target.path) == unrelated.path, "symlink retained")
        }
        try test("another installer lock prevents replacement") {
            let fixture = try Fixture()
            let lock = try InstallLock(parent: fixture.parent)
            try expectFailure { _ = try fixture.transaction().install() }
            withExtendedLifetime(lock) {}
            try require(try fixture.marker() == "old", "locked app retained")
        }
        try test("downgrade is rejected before replacement") {
            let fixture = try Fixture()
            try Fixture.writeApp(at: fixture.target, version: "9.0.0", marker: "newer")
            try expectFailure { _ = try fixture.transaction().install() }
            try require(try fixture.marker() == "newer", "newer app retained")
        }
        try test("a destination changed during preparation is retained") {
            let fixture = try Fixture()
            try expectFailure { _ = try fixture.transaction(changeDestination: true).install() }
            try require(try fixture.marker() == "changed-by-other-operation", "changed destination retained")
            try require(fixture.calls.isEmpty, "no old-app commands after destination changed")
        }
        try test("rollback obstruction preserves backup and unrelated destination") {
            let fixture = try Fixture()
            try expectFailure { _ = try fixture.transaction(obstructRollback: true).install() }
            try require(try fixture.marker() == "changed-by-other-operation", "foreign destination retained")
            let retained = try FileManager.default.contentsOfDirectory(at: fixture.parent, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix(".MonkeyInstall-") }
            try require(retained.count == 1, "recovery directory retained")
            try require(try String(contentsOf: retained[0].appendingPathComponent("PreviousMonkey.app/marker")) == "old", "old backup retained")
        }
        try test("a running new version prevents unsafe rollback") {
            let fixture = try Fixture()
            try expectFailure { _ = try fixture.transaction(failLaunch: true, refuseRollbackExit: true).install() }
            try require(try fixture.marker() == "new", "running new app retained")
            let retained = try FileManager.default.contentsOfDirectory(at: fixture.parent, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix(".MonkeyInstall-") }
            try require(retained.count == 1, "rollback recovery directory retained")
            try require(try String(contentsOf: retained[0].appendingPathComponent("PreviousMonkey.app/marker")) == "old", "old backup retained while new app runs")
            try fixture.assertDataPreserved()
        }
        try test("a destination changed while waiting for exit is retained") {
            let fixture = try Fixture()
            try expectFailure { _ = try fixture.transaction(changeDuringStop: true).install() }
            try require(try fixture.marker() == "changed-by-other-operation", "destination changed during stop retained")
            try require(fixture.calls.isEmpty, "no new app commands after exit-time change")
        }
        try test("a lower build of the same version is rejected") {
            let fixture = try Fixture()
            try Fixture.writeApp(at: fixture.target, version: "0.2.2", marker: "newer-build", build: "2")
            try expectFailure { _ = try fixture.transaction().install() }
            try require(try fixture.marker() == "newer-build", "same-version newer build retained")
            try require(fixture.calls.isEmpty, "no commands for a build downgrade")
        }
        print("\(passed) isolated installer checks passed. No user installation was modified.")
    }

    private static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw InstallerFailure.message("Self-test failed: \(message)") }
    }

    private static func expectFailure(_ body: () throws -> Void) throws {
        do { try body() } catch { return }
        throw InstallerFailure.message("Self-test expected failure but operation succeeded")
    }

    private final class Fixture {
        let root: URL
        let parent: URL
        let source: URL
        let target: URL
        var calls: [String] = []

        init(existing: Bool = true) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyInstallerSelfTest-\(UUID().uuidString)")
            parent = root.appendingPathComponent("Input Methods")
            source = root.appendingPathComponent("Payload/Monkey.app")
            target = parent.appendingPathComponent("Monkey.app")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.appendingPathComponent("UserData"), withIntermediateDirectories: false)
            try "keep-user-dictionary-and-credentials".write(to: root.appendingPathComponent("UserData/keep"), atomically: true, encoding: .utf8)
            try Self.writeApp(at: source, version: "0.2.2", marker: "new")
            if existing { try Self.writeApp(at: target, version: "0.2.0", marker: "old") }
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        static func writeApp(at app: URL, version: String, marker: String, identifier: String = InstalledApp.bundleID, build: String = "1") throws {
            let manager = FileManager.default
            try manager.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": InstalledApp.executableName,
                "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version, "CFBundleVersion": build, "LSMinimumSystemVersion": "13.0"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: app.appendingPathComponent("Contents/Info.plist"))
            let executable = app.appendingPathComponent("Contents/MacOS/\(InstalledApp.executableName)")
            try Data("fixture-not-executed".utf8).write(to: executable)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            try marker.write(to: app.appendingPathComponent("marker"), atomically: true, encoding: .utf8)
        }

        func marker() throws -> String { try String(contentsOf: target.appendingPathComponent("marker")) }
        func assertDataPreserved() throws {
            try require(try String(contentsOf: root.appendingPathComponent("UserData/keep")) == "keep-user-dictionary-and-credentials", "user data retained")
        }

        func transaction(failFinalValidation: Bool = false, failPreparation: Bool = false,
                         deferRegistration: Bool = false, oldStillRunning: Bool = false,
                         failLaunch: Bool = false, changeDestination: Bool = false,
                         obstructRollback: Bool = false, refuseRollbackExit: Bool = false,
                         changeDuringStop: Bool = false) -> InstallTransaction {
            InstallTransaction(parent: parent, prepare: { stage in
                if failPreparation { throw InstallerFailure.message("injected preparation failure") }
                let incoming = stage.appendingPathComponent("Monkey.app")
                try FileManager.default.copyItem(at: self.source, to: incoming)
                if changeDestination {
                    try FileManager.default.moveItem(at: self.target, to: self.root.appendingPathComponent("ChangedOld.app"))
                    try Self.writeApp(at: self.target, version: "0.2.0", marker: "changed-by-other-operation")
                }
                return incoming
            }, verify: { app in
                if failFinalValidation && app.standardizedFileURL.path == self.target.standardizedFileURL.path {
                    throw InstallerFailure.message("injected final validation failure")
                }
                return try InstalledApp.read(at: app)
            }, command: { _, arguments in
                self.calls.append(arguments[0])
                if obstructRollback && arguments == ["--register"] {
                    try FileManager.default.moveItem(at: self.target, to: self.root.appendingPathComponent("MovedNew.app"))
                    try Self.writeApp(at: self.target, version: "0.2.0", marker: "changed-by-other-operation")
                    throw InstallerFailure.message("injected rollback obstruction")
                }
                if failLaunch && arguments == ["--register"] { throw InstallerFailure.message("injected command launch failure") }
                return CommandResult(status: deferRegistration ? 1 : 0, output: "fixture")
            }, ensureStopped: { _ in
                if oldStillRunning { throw InstallerFailure.message("injected still-running process") }
                if changeDuringStop {
                    try FileManager.default.moveItem(at: self.target, to: self.root.appendingPathComponent("ChangedDuringStop.app"))
                    try Self.writeApp(at: self.target, version: "0.2.0", marker: "changed-by-other-operation")
                }
                if refuseRollbackExit && self.calls.contains("--register") {
                    throw InstallerFailure.message("injected new process refusing rollback exit")
                }
            })
        }
    }
}
