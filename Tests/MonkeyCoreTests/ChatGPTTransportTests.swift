import Foundation
import Network
import XCTest
@testable import MonkeyCore

final class ChatGPTTransportTests: XCTestCase {
    @MainActor
    func testActualURLSessionTransportPreservesEventBoundariesAndUnicode() async throws {
        let payload = ": heartbeat\r\nevent: response.output_text.delta\r\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"你好 \"}\r\n\r\ndata: {\"type\":\"response.output_text.delta\",\"delta\":\"world\"}\r\n\r\nevent: response.completed\r\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\r\n\r\n"
        let server = try LocalSSETestServer(payload: payload)
        let url = try await server.start()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        var deltas: [String] = []
        let result = try await ChatGPTSSETransport.decode(bytes, onDelta: { deltas.append($0) })
        XCTAssertEqual(result, "你好 world")
        XCTAssertEqual(deltas, ["你好 ", "world"])
    }

    @MainActor
    func testActualTransportRejectsLateQuotaFailureAndInterruptedStream() async throws {
        for terminal in ["data: {\"type\":\"response.failed\",\"response\":{\"error\":{\"code\":\"subscription_sharing_usage_limit_exceeded\"}}}\n\n", ""] {
            let payload = "data: {\"type\":\"response.output_text.delta\",\"delta\":\"unfinished\"}\n\n" + terminal
            let server = try LocalSSETestServer(payload: payload)
            let url = try await server.start()
            let session = URLSession(configuration: .ephemeral)
            do {
                let (bytes, _) = try await session.bytes(from: url)
                _ = try await ChatGPTSSETransport.decode(bytes)
                XCTFail("A partial stream must not become a completed translation")
            } catch {
                XCTAssertTrue(error is ChatGPTError)
            }
            session.invalidateAndCancel()
            server.stop()
        }
    }

    func testByteLineDecoderPreservesLFCRLFAndLoneCRBlankLines() throws {
        var decoder = ChatGPTSSELineDecoder()
        var lines: [String] = []
        for byte in Data("one\n\ntwo\r\n\r\n三\r\rfour".utf8) {
            if let line = try decoder.consume(byte) { lines.append(line) }
        }
        if let line = try decoder.finish() { lines.append(line) }
        XCTAssertEqual(lines, ["one", "", "two", "", "三", "", "four"])
    }
}

/// A real loopback HTTP/SSE server; neither credentials nor external services are used.
@MainActor
private final class LocalSSETestServer {
    private let listener: NWListener
    private let payload: Data
    private let queue = DispatchQueue(label: "monkey.sse-transport-tests")

    init(payload: String) throws {
        self.payload = Data(payload.utf8)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> URL {
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { _, _, _, _ in
                    Task { @MainActor in self.send(connection) }
                }
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            var pending: CheckedContinuation<URL, Error>? = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self, let continuation = pending else { return }
                    switch state {
                    case .ready:
                        pending = nil
                        continuation.resume(returning: URL(string: "http://127.0.0.1:\(self.listener.port!.rawValue)/events")!)
                    case let .failed(error):
                        pending = nil
                        continuation.resume(throwing: error)
                    default: break
                    }
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() { listener.cancel() }

    private func send(_ connection: NWConnection) {
        let header = Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
        // Deliberately split the first Chinese character inside its UTF-8 encoding.
        let split = payload.firstIndex(where: { $0 >= 0x80 }).map { payload.distance(from: payload.startIndex, to: $0) + 1 } ?? payload.count / 2
        connection.send(content: header + payload.prefix(split), completion: .contentProcessed { [payload] _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.015) {
                connection.send(content: Data(payload.dropFirst(split)), completion: .contentProcessed { _ in connection.cancel() })
            }
        })
    }
}
