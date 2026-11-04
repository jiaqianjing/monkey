import Darwin
import Foundation
import XCTest
@testable import MonkeyCore

final class ChatGPTAccountMetadataTests: XCTestCase {
    func testIndependentProcessesPreserveConcurrentAccountsAndDisabledClients() throws {
        let environment = ProcessInfo.processInfo.environment
        if let suite = environment["MONKEY_METADATA_TEST_SUITE"],
           let directoryPath = environment["MONKEY_METADATA_TEST_DIRECTORY"],
           let index = environment["MONKEY_METADATA_TEST_INDEX"] {
            let directory = URL(fileURLWithPath: directoryPath)
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            for _ in 0..<12 {
                try ChatGPTAccountMetadata.withLock(defaults: defaults, directory: directory, domain: suite) {
                    var accounts = try ChatGPTAccountMetadata.accounts(defaults)
                    let id = "client-\(index)"
                    accounts.removeAll { $0.clientID == id }
                    accounts.append(ChatGPTAccount(clientID: id, subject: id, email: "\(id)@example.invalid"))
                    defaults.set(try JSONEncoder().encode(accounts), forKey: "ChatGPT.accounts")
                    ChatGPTAccountMetadata.setDisabled(id, disabled: true, defaults: defaults)
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
            try Data("done".utf8).write(to: directory.appendingPathComponent("done-\(index)"))
            return
        }
        let suite = "MonkeyCoreTests.metadata.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyMetadata-\(UUID().uuidString)")
        defer {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let count = 6
        var children: [Process] = []
        for index in 0..<count {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            child.arguments = ["xctest", "-XCTest", "MonkeyCoreTests.ChatGPTAccountMetadataTests/testIndependentProcessesPreserveConcurrentAccountsAndDisabledClients", Bundle(for: Self.self).bundleURL.path]
            var childEnvironment = environment
            childEnvironment["MONKEY_METADATA_TEST_SUITE"] = suite
            childEnvironment["MONKEY_METADATA_TEST_DIRECTORY"] = directory.path
            childEnvironment["MONKEY_METADATA_TEST_INDEX"] = String(index)
            child.environment = childEnvironment
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            try child.run()
            children.append(child)
        }
        for child in children {
            child.waitUntilExit()
            XCTAssertEqual(child.terminationStatus, 0, "Child metadata transaction failed")
        }
        for index in 0..<count {
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("done-\(index)").path), "Child did not run the test body")
        }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try ChatGPTAccountMetadata.withLock(defaults: defaults, directory: directory, domain: suite) {
            let expected = Set((0..<count).map { "client-\($0)" })
            XCTAssertEqual(Set(try ChatGPTAccountMetadata.accounts(defaults).map(\.clientID)), expected)
            XCTAssertEqual(Set(defaults.stringArray(forKey: "ChatGPT.disabledClients") ?? []), expected)
        }
    }
    func testBusyMetadataLockFailsWithinBoundWithoutRunningTransaction() throws {
        let suite = "MonkeyCoreTests.lock-timeout.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MonkeyLock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fd = Darwin.open(directory.appendingPathComponent("accounts.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { Darwin.close(fd) }
        XCTAssertEqual(flock(fd, LOCK_EX | LOCK_NB), 0)
        defer { flock(fd, LOCK_UN) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var ran = false
        let start = Date()
        XCTAssertThrowsError(try ChatGPTAccountMetadata.withLock(defaults: defaults, directory: directory, domain: suite) { ran = true })
        XCTAssertFalse(ran)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

}
