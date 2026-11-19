import Foundation
import Network
import RaccoonData
import RaccoonDomain
import Synchronization
import Testing

@Suite struct NetworkMockListeningTests {
    private static let ok = MockReply(
        status: 201, headers: [.init(name: "X-Thing", value: "one")], body: Data("hello".utf8), delay: .zero
    )

    private static func url(_ listener: MockListener, _ path: String = "/users") -> URL {
        URL(string: "http://127.0.0.1:\(listener.port)\(path)")!
    }

    @Test func `binds a free port and answers a URLSession request with the framed reply`() async throws {
        let listener = try await NetworkMockListening().listen(port: nil) { _ in Self.ok }
        defer { listener.stop() }

        let (data, response) = try await URLSession.shared.data(from: Self.url(listener))
        let http = try #require(response as? HTTPURLResponse)
        #expect(listener.port != 0)
        #expect(http.statusCode == 201)
        #expect(http.value(forHTTPHeaderField: "X-Thing") == "one")
        #expect(http.value(forHTTPHeaderField: "Content-Length") == "5")
        #expect(http.value(forHTTPHeaderField: "Connection") == "close")
        #expect(data == Data("hello".utf8))
    }

    @Test func `a second bind on a taken port is portInUse`() async throws {
        let first = try await NetworkMockListening().listen(port: nil) { _ in Self.ok }
        defer { first.stop() }

        await #expect(throws: MockError.portInUse(first.port)) {
            try await NetworkMockListening().listen(port: first.port) { _ in Self.ok }
        }
    }

    @Test func `a port held by a wildcard listener is portInUse`() async throws {
        let other = try NWListener(using: .tcp, on: .any)
        other.newConnectionHandler = { $0.cancel() }
        let ready = Mutex<UInt16?>(nil)
        other.stateUpdateHandler = { state in
            if case .ready = state { ready.withLock { $0 = other.port?.rawValue } }
        }
        other.start(queue: DispatchQueue(label: "wildcard"))
        defer { other.cancel() }
        try await waitUntil { ready.withLock { $0 } != nil }
        let port = try #require(ready.withLock { $0 })

        await #expect(throws: MockError.portInUse(port)) {
            try await NetworkMockListening().listen(port: port) { _ in Self.ok }
        }
    }

    @Test func `binds the port asked for, again right after a stop that served a request`() async throws {
        let first = try await NetworkMockListening().listen(port: nil) { _ in Self.ok }
        let port = first.port
        _ = try await URLSession.shared.data(from: Self.url(first))
        first.stop()

        // stop() returns before the socket is released, so a rebind may need a few milliseconds.
        var listener: MockListener?
        for _ in 0..<100 where listener == nil {
            do { listener = try await NetworkMockListening().listen(port: port) { _ in Self.ok } } catch {
                try #require(error == .portInUse(port))
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        let rebound = try #require(listener)
        defer { rebound.stop() }
        #expect(rebound.port == port)
        let (_, response) = try await URLSession.shared.data(from: Self.url(rebound))
        #expect((response as? HTTPURLResponse)?.statusCode == 201)
    }

    @Test func `is reachable on loopback only`() async throws {
        let listener = try await NetworkMockListening().listen(port: nil) { _ in Self.ok }
        defer { listener.stop() }

        guard let address = Self.nonLoopbackIPv4() else { return }
        var request = URLRequest(url: URL(string: "http://\(address):\(listener.port)/")!)
        request.timeoutInterval = 2
        await #expect(throws: URLError.self) { try await URLSession.shared.data(for: request) }
    }

    @Test func `the handler gets the parsed head, and a body is drained before the reply`() async throws {
        let seen = Mutex<[MockRequestHead]>([])
        let listener = try await NetworkMockListening().listen(port: nil) { head in
            seen.withLock { $0.append(head) }
            return Self.ok
        }
        defer { listener.stop() }

        var request = URLRequest(url: Self.url(listener, "/users/42?x=1"))
        request.httpMethod = "POST"
        request.httpBody = Data(repeating: UInt8(ascii: "a"), count: 200_000)
        let (data, response) = try await URLSession.shared.data(for: request)

        #expect((response as? HTTPURLResponse)?.statusCode == 201)
        #expect(data == Data("hello".utf8))
        let head = try #require(seen.withLock { $0.first })
        #expect(head.method == "POST")
        #expect(head.path == ["users", "42"])
        #expect(head.bodyLength == 200_000)
    }

    @Test func `a head split across reads is parsed once it is whole`() async throws {
        let listener = try await NetworkMockListening().listen(port: nil) { _ in Self.ok }
        defer { listener.stop() }

        let client = RawClient(port: listener.port)
        await client.send("GET /users HT")
        try await Task.sleep(for: .milliseconds(50))
        await client.send("TP/1.1\r\nHost: x\r\n\r\n")
        let reply = String(decoding: await client.readToEnd(within: .seconds(2)).data, as: UTF8.self)

        #expect(reply.hasPrefix("HTTP/1.1 201 Created\r\n"))
    }

    @Test(arguments: [
        ("garbage\r\n\r\n", 400),
        ("POST /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n", 501),
        ("POST /x HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n", 413),
    ])
    func `a request that does not parse gets its status and the handler is never called`(raw: String, status: Int) async throws {
        let calls = Mutex(0)
        let listener = try await NetworkMockListening().listen(port: nil) { _ in
            calls.withLock { $0 += 1 }
            return Self.ok
        }
        defer { listener.stop() }

        let client = RawClient(port: listener.port)
        await client.send(raw)
        let reply = String(decoding: await client.readToEnd(within: .seconds(2)).data, as: UTF8.self)

        #expect(reply.hasPrefix("HTTP/1.1 \(status) "))
        #expect(calls.withLock { $0 } == 0)
    }

    @Test func `the reply waits out its delay`() async throws {
        let delayed = MockReply(status: 200, headers: [], body: Data(), delay: .milliseconds(300))
        let listener = try await NetworkMockListening().listen(port: nil) { _ in delayed }
        defer { listener.stop() }

        let started = ContinuousClock.now
        _ = try await URLSession.shared.data(from: Self.url(listener))
        #expect(ContinuousClock.now - started >= .milliseconds(300))
    }

    @Test func `a client that goes away during the delay is not an error and the listener keeps serving`() async throws {
        let calls = Mutex(0)
        let listener = try await NetworkMockListening().listen(port: nil) { _ in
            calls.withLock { $0 += 1 }
            return MockReply(status: 200, headers: [], body: Data("late".utf8), delay: .milliseconds(200))
        }
        defer { listener.stop() }

        let gone = RawClient(port: listener.port)
        await gone.send("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
        try await waitUntil { calls.withLock { $0 } == 1 }
        gone.cancel()
        try await Task.sleep(for: .milliseconds(400))

        let (data, _) = try await URLSession.shared.data(from: Self.url(listener))
        #expect(data == Data("late".utf8))
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func `stop during a delay closes the connection and returns promptly`() async throws {
        let calls = Mutex(0)
        let listener = try await NetworkMockListening().listen(port: nil) { _ in
            calls.withLock { $0 += 1 }
            return MockReply(status: 200, headers: [], body: Data(), delay: .seconds(30))
        }

        let client = RawClient(port: listener.port)
        await client.send("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
        try await waitUntil { calls.withLock { $0 } == 1 }

        let stopped = ContinuousClock.now
        listener.stop()
        #expect(ContinuousClock.now - stopped < .milliseconds(200))
        let closed = await client.readToEnd(within: .seconds(2))

        #expect(!closed.timedOut)
        #expect(closed.data.isEmpty)
        #expect(ContinuousClock.now - stopped < .seconds(1))
    }

    @Test func `stop closes a connection still waiting for the rest of its head, and refuses new ones`() async throws {
        let listener = try await NetworkMockListening().listen(port: nil) { _ in Self.ok }
        let client = RawClient(port: listener.port)
        await client.send("GET / HT")
        try await Task.sleep(for: .milliseconds(100))

        listener.stop()
        listener.stop()

        #expect(!(await client.readToEnd(within: .seconds(2))).timedOut)
        let after = RawClient(port: listener.port)
        await after.send("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
        #expect(await after.readToEnd(within: .milliseconds(300)).data.isEmpty)
    }

    private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            try #require(ContinuousClock.now < deadline, "condition not met in 3 s")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The first up, non-loopback IPv4 address of this machine, if it has one.
    private static func nonLoopbackIPv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let info = entry.pointee
            guard let address = info.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  Int32(info.ifa_flags) & (IFF_UP | IFF_LOOPBACK) == IFF_UP else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            return String(cString: host)
        }
        return nil
    }
}

/// A bare TCP client, so a test can send bytes URLSession would never send and see when the server closes.
private final class RawClient: Sendable {
    private let connection: NWConnection

    init(port: UInt16) {
        connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        connection.start(queue: DispatchQueue(label: "RawClient"))
    }

    func send(_ text: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in continuation.resume() })
        }
    }

    func cancel() {
        connection.cancel()
    }

    /// Everything received until the peer closes, or until `limit`, when the client closes itself.
    func readToEnd(within limit: Duration) async -> (data: Data, timedOut: Bool) {
        let expired = Expired()
        let timeout = Task { [connection] in
            try await Task.sleep(for: limit)
            expired.flag.withLock { $0 = true }
            connection.cancel()
        }
        defer { timeout.cancel() }
        var data = Data()
        while true {
            let (chunk, finished) = await withCheckedContinuation { (continuation: CheckedContinuation<(Data?, Bool), Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { chunk, _, isComplete, error in
                    continuation.resume(returning: (chunk, isComplete || error != nil))
                }
            }
            data += chunk ?? Data()
            if finished { return (data, expired.flag.withLock { $0 }) }
        }
    }

    private final class Expired: Sendable {
        let flag = Mutex(false)
    }
}
