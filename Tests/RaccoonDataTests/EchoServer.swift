import Foundation
import Network
import Security
import Synchronization
import Testing

/// Runs `body` against a fresh echo server on a free localhost port, and stops it when `body` returns.
func withEchoServer<T>(tls: Bool = false, _ body: (EchoServer) async throws -> T) async throws -> T {
    let server = try await EchoServer.start(tls: tls)
    defer { server.stop() }
    return try await body(server)
}

/// A test-only HTTP/1.1 server that answers with the raw bytes it received, so a test can see
/// exactly what URLSession put on the wire. Every reply closes the connection.
///
///     /delay/<ms>   waits, then echoes
///     /redirect     302 to /echo
///     /bytes/<n>    a body of n bytes
///     /headers      two Set-Cookie headers and two others out of alphabetical order
///     /gzip         "compressed hello", gzip-encoded with Content-Encoding: gzip, whatever was asked
///     anything else echoes
final class EchoServer: Sendable {
    let port: UInt16
    let scheme: String
    private let listener: NWListener
    private let queue: DispatchQueue
    private let received = Mutex<[Data]>([])

    /// Every request's raw bytes, head and body, in arrival order.
    var requests: [Data] { received.withLock { $0 } }

    func url(_ path: String) -> URL {
        URL(string: "\(scheme)://127.0.0.1:\(port)\(path)")!
    }

    func stop() {
        listener.cancel()
    }

    static func start(tls: Bool) async throws -> EchoServer {
        let parameters = tls ? NWParameters(tls: try tlsOptions(), tcp: .init()) : .tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "EchoServer")
        let port = try await ready(listener, on: queue)
        return EchoServer(listener: listener, queue: queue, port: port, scheme: tls ? "https" : "http")
    }

    private init(listener: NWListener, queue: DispatchQueue, port: UInt16, scheme: String) {
        self.listener = listener
        self.queue = queue
        self.port = port
        self.scheme = scheme
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            connection.start(queue: queue)
            receive(on: connection, buffer: Data())
        }
    }

    private static func ready(_ listener: NWListener, on queue: DispatchQueue) async throws -> UInt16 {
        try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            listener.newConnectionHandler = { $0.cancel() }
            listener.stateUpdateHandler = { state in
                let result: Result<UInt16, any Error>? = switch state {
                case .ready: .success(listener.port!.rawValue)
                case .failed(let error): .failure(error)
                case .cancelled: .failure(CancellationError())
                default: nil
                }
                guard let result, resumed.withLock({ done in defer { done = true }; return !done }) else { return }
                continuation.resume(with: result)
            }
            listener.start(queue: queue)
        }
    }

    /// The self-signed localhost identity in Fixtures, imported into memory only.
    private static func tlsOptions() throws -> NWProtocolTLS.Options {
        let url = try #require(Bundle.module.url(forResource: "localhost", withExtension: "p12", subdirectory: "Fixtures"))
        let options = [kSecImportExportPassphrase: "raccoon", kSecImportToMemoryOnly: true] as CFDictionary
        var items: CFArray?
        let status = SecPKCS12Import(try Data(contentsOf: url) as CFData, options, &items)
        try #require(status == errSecSuccess, "SecPKCS12Import: \(status)")
        let first = try #require((items as? [[String: Any]])?.first)
        let identity = first[kSecImportItemIdentity as String] as! SecIdentity

        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(tls.securityProtocolOptions, try #require(sec_identity_create(identity)))
        return tls
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            let buffer = buffer + (data ?? Data())
            if Self.isComplete(buffer) {
                received.withLock { $0.append(buffer) }
                respond(to: buffer, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    /// The head is in, and so is the body its Content-Length or chunked framing announces.
    private static func isComplete(_ buffer: Data) -> Bool {
        guard let headEnd = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else { return false }
        let head = String(decoding: buffer[..<headEnd.lowerBound], as: UTF8.self).lowercased()
        let body = buffer[headEnd.upperBound...]
        if head.contains("\r\ntransfer-encoding: chunked") {
            return body.firstRange(of: Data("0\r\n\r\n".utf8)) != nil
        }
        let length = head.split(separator: "\r\n")
            .first { $0.hasPrefix("content-length:") }
            .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
        return body.count >= length
    }

    private func respond(to request: Data, on connection: NWConnection) {
        let path = String(decoding: request.prefix { $0 != UInt8(ascii: "\r") }, as: UTF8.self)
            .split(separator: " ").dropFirst().first.map(String.init) ?? "/"
        let parts = path.split(separator: "/")

        switch (parts.first, parts.dropFirst().first.flatMap { Int($0) }) {
        case ("delay", let milliseconds?):
            queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds)) { [weak self] in
                self?.send(status: "200 OK", headers: [], body: request, on: connection)
            }
        case ("redirect", _):
            send(status: "302 Found", headers: ["Location: /echo"], body: Data(), on: connection)
        case ("headers", _):
            send(status: "200 OK", headers: Self.replyHeaders, body: Data(), on: connection)
        case ("gzip", _):
            send(status: "200 OK", headers: ["Content-Encoding: gzip"], body: Self.gzipBody, on: connection)
        case ("bytes", let count?):
            sendHead(status: "200 OK", headers: [], contentLength: count, on: connection)
            sendFiller(remaining: count, on: connection)
        default:
            send(status: "200 OK", headers: [], body: request, on: connection)
        }
    }

    /// What /headers adds after the fixed head, in this order.
    static let replyHeaders = ["Z-Last: 1", "Set-Cookie: a=1; Path=/", "A-First: 2", "Set-Cookie: b=2; Path=/"]

    /// "compressed hello" through gzip, mtime 0.
    static let gzipBody = Data(base64Encoded: "H4sIAAAAAAAC/0vOzy0oSi0uTk1RyEjNyckHALYBmUYQAAAA")!

    private func sendHead(status: String, headers: [String], contentLength: Int, on connection: NWConnection) {
        let lines = ["HTTP/1.1 \(status)", "Content-Length: \(contentLength)", "Content-Type: application/octet-stream",
                     "Connection: close"] + headers
        connection.send(content: Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8), completion: .idempotent)
    }

    private func send(status: String, headers: [String], body: Data, on connection: NWConnection) {
        sendHead(status: status, headers: headers, contentLength: body.count, on: connection)
        finish(with: body, on: connection)
    }

    /// One 64 KB chunk at a time, so a large body is never held in memory whole.
    private func sendFiller(remaining: Int, on connection: NWConnection) {
        let chunk = Data(repeating: UInt8(ascii: "a"), count: min(remaining, 65_536))
        guard remaining > chunk.count else { return finish(with: chunk, on: connection) }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error == nil else { return connection.cancel() }
            self?.sendFiller(remaining: remaining - chunk.count, on: connection)
        })
    }

    private func finish(with data: Data, on connection: NWConnection) {
        connection.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
