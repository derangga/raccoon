import Foundation

/// The Mock Server's socket. Binds 127.0.0.1 only; `port` nil lets the system pick a free one.
/// For each connection it reads one request, drops its body, calls `handler` and writes the
/// MockReply it returns, after the reply's delay, then closes.
public protocol MockListening: Sendable {
    func listen(
        port: UInt16?,
        handler: @escaping @Sendable (MockRequestHead) async -> MockReply
    ) async throws(MockError) -> MockListener
}

/// A running listener. `stop()` closes the socket, every open connection and every pending delay.
public struct MockListener: Sendable {
    /// The port actually bound.
    public let port: UInt16
    private let onStop: @Sendable () -> Void

    public init(port: UInt16, stop: @escaping @Sendable () -> Void) {
        self.port = port
        onStop = stop
    }

    /// Returns promptly; calling it again does nothing.
    public func stop() {
        onStop()
    }
}

/// Only starting can fail: a connection's failures close that connection and nothing else.
public enum MockError: Error, Equatable, Sendable {
    /// The requested port is taken.
    case portInUse(UInt16)
    /// The listener's own reason.
    case failed(String)
}
