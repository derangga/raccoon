import Foundation
import Network
import RaccoonDomain
import Synchronization

/// The live MockListening: an NWListener bound to 127.0.0.1, never to all interfaces, so nothing off
/// the machine can reach it. One request per connection, answered off the main actor.
public struct NetworkMockListening: MockListening {
    public init() {}

    public func listen(
        port: UInt16?,
        handler: @escaping @Sendable (MockRequestHead) async -> MockReply
    ) async throws(MockError) -> MockListener {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port ?? 0) ?? .any)
        let listener: NWListener
        do { listener = try NWListener(using: parameters) } catch { throw Server.mockError(error, port: port) }
        let server = Server(listener: listener, handler: handler)
        let bound = try await server.start(requested: port)
        return MockListener(port: bound, stop: { server.stop() })
    }
}

private final class Server: Sendable {
    private struct State {
        var stopped = false
        var live: [UUID: (connection: NWConnection, task: Task<Void, Never>)] = [:]
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "NetworkMockListening")
    private let handler: @Sendable (MockRequestHead) async -> MockReply
    private let state = Mutex(State())

    init(listener: NWListener, handler: @escaping @Sendable (MockRequestHead) async -> MockReply) {
        self.listener = listener
        self.handler = handler
    }

    /// Waits for `.ready` and returns the bound port. The handlers hold `self` until `stop()`.
    func start(requested: UInt16?) async throws(MockError) -> UInt16 {
        let result: Result<UInt16, MockError> = await withCheckedContinuation { continuation in
            let resumed = Mutex(false)
            listener.newConnectionHandler = { [self] in accept($0) }
            listener.stateUpdateHandler = { [self, listener] newState in
                let result: Result<UInt16, MockError>? = switch newState {
                case .ready: listener.port.map { .success($0.rawValue) } ?? .failure(.failed("no port bound"))
                case .waiting(let error): .failure(Self.mockError(error, port: requested))
                case .failed(let error): .failure(Self.mockError(error, port: requested))
                case .cancelled: .failure(.failed("cancelled"))
                default: nil
                }
                guard let result else { return }
                if resumed.withLock({ done in defer { done = true }; return !done }) {
                    continuation.resume(returning: result)
                } else if case .failure = result {
                    stop()
                }
            }
            listener.start(queue: queue)
        }
        do { return try result.get() } catch {
            stop()
            throw error
        }
    }

    /// Cancels the listener, every connection and every pending delay. Idempotent.
    func stop() {
        let live = state.withLock { current in
            current.stopped = true
            defer { current.live = [:] }
            return Array(current.live.values)
        }
        listener.cancel()
        listener.newConnectionHandler = nil
        listener.stateUpdateHandler = nil
        for (connection, task) in live {
            task.cancel()
            connection.cancel()
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        state.withLock { current in
            guard !current.stopped else { return connection.cancel() }
            connection.start(queue: queue)
            let task = Task { [self] in
                await serve(connection)
                state.withLock { $0.live[id] = nil }
            }
            current.live[id] = (connection, task)
        }
    }

    // shortcut: no idle or read timeout, so a client that trickles bytes or declares a body it never
    // sends holds its connection until stop(); upgrade when a client needs it.
    // shortcut: no cap on concurrent connections; upgrade when a local client opens thousands.
    /// Read, drop the body, ask the handler, wait out the delay, write, close. Every early `return`
    /// is a client that went away or a stop: the connection closes and nothing is reported.
    private func serve(_ connection: NWConnection) async {
        defer { connection.cancel() }
        var buffer = Data()
        let reply: MockReply
        read: while true {
            guard let chunk = await Self.receive(connection, max: 65_536) else { return }
            buffer += chunk
            switch MockRequestHead.parse(buffer) {
            case .needMore:
                continue
            case .failure(let status, _):
                reply = MockReply(status: status, headers: [], body: Data(), delay: .zero)
                break read
            case .head(let head, _, var remaining):
                while remaining > 0 {
                    guard let chunk = await Self.receive(connection, max: min(remaining, 65_536)) else { return }
                    remaining -= chunk.count
                }
                guard !Task.isCancelled else { return }
                reply = await handler(head)
                break read
            }
        }
        guard (try? await Task.sleep(for: reply.delay)) != nil else { return }
        await Self.send(connection, MockReply.bytes(reply))
    }

    /// nil when the peer closed, errored or the connection was cancelled.
    private static func receive(_ connection: NWConnection, max: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: max) { data, _, _, error in
                continuation.resume(returning: error == nil ? data.flatMap { $0.isEmpty ? nil : $0 } : nil)
            }
        }
    }

    /// Returns once the bytes are handed to the socket, or the write failed.
    private static func send(_ connection: NWConnection, _ data: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in continuation.resume() })
        }
    }

    static func mockError(_ error: any Error, port: UInt16?) -> MockError {
        guard case .posix(let code)? = error as? NWError else { return .failed(String(describing: error)) }
        if code == .EADDRINUSE { return .portInUse(port ?? 0) }
        let text = String(cString: strerror(code.rawValue))
        return .failed(text.prefix(1).lowercased() + text.dropFirst())
    }
}
