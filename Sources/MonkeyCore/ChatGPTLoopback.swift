import Foundation
import Network

/// The OAuth callback binds IPv4 loopback only, uses an ephemeral port, and expires.
@MainActor
final class ChatGPTLoopbackServer {
    private var listener: NWListener?
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var callbackContinuation: CheckedContinuation<URL, Error>?
    private var earlyCallback: URL?
    private var timeoutTask: Task<Void, Never>?
    private var port: UInt16 = 0
    private let queue = DispatchQueue(label: "org.monkey.inputmethod.oauth-loopback")

    func start() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard let assigned = listener.port?.rawValue else {
                            self.stop(error: ChatGPTError.message("无法启动本机登录回调。")); return
                        }
                        self.port = assigned
                        let url = URL(string: "http://127.0.0.1:\(assigned)/auth/callback")!
                        self.startContinuation?.resume(returning: url)
                        self.startContinuation = nil
                    case .failed:
                        self.stop(error: ChatGPTError.message("本机登录回调启动失败，请重试。"))
                    default: break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.receive(connection, accumulated: Data()) }
            }
            listener.start(queue: queue)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000_000)
                guard !Task.isCancelled else { return }
                self?.stop(error: ChatGPTError.message("登录等待已超时，请重新登录。"))
            }
        }
    }

    func callback() async throws -> URL {
        if let earlyCallback { return earlyCallback }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { callbackContinuation = $0 }
        }, onCancel: { Task { @MainActor in self.stop(error: CancellationError()) } })
    }

    func stop(error: Error = CancellationError()) {
        timeoutTask?.cancel()
        timeoutTask = nil
        listener?.cancel()
        listener = nil
        startContinuation?.resume(throwing: error)
        startContinuation = nil
        callbackContinuation?.resume(throwing: error)
        callbackContinuation = nil
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        if accumulated.isEmpty { connection.start(queue: queue) }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self else { connection.cancel(); return }
                var bytes = accumulated
                if let data { bytes.append(data) }
                guard bytes.count <= 16_384 else { self.respond(connection, code: "413 Payload Too Large", body: "Request rejected."); return }
                guard let string = String(data: bytes, encoding: .utf8), string.contains("\r\n\r\n") else {
                    if isComplete || error != nil { connection.cancel() }
                    else { self.receive(connection, accumulated: bytes) }
                    return
                }
                let first = string.components(separatedBy: "\r\n").first ?? ""
                let request = first.split(separator: " ")
                guard request.count == 3, request[0] == "GET",
                      request[1].hasPrefix("/auth/callback?"),
                      let url = URL(string: "http://127.0.0.1:\(self.port)\(request[1])") else {
                    self.respond(connection, code: "404 Not Found", body: "Not found."); return
                }
                // The client validates state and authorization parameters before exchanging a code.
                self.respond(connection, code: "200 OK", body: "<!doctype html><meta charset=\"utf-8\"><title>Monkey</title><style>body{font:18px system-ui;max-width:600px;margin:15vh auto;padding:32px;line-height:1.7}</style><h1>返回 Monkey</h1><p>登录信息已送回 Monkey。请返回应用查看连接结果，然后关闭此页面。</p>")
                self.earlyCallback = url
                self.callbackContinuation?.resume(returning: url)
                self.callbackContinuation = nil
                self.timeoutTask?.cancel()
                self.listener?.cancel()
                self.listener = nil
            }
        }
    }

    private func respond(_ connection: NWConnection, code: String, body: String) {
        let bodyData = Data(body.utf8)
        let header = "HTTP/1.1 \(code)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bodyData.count)\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + bodyData, completion: .contentProcessed { _ in connection.cancel() })
    }
}
