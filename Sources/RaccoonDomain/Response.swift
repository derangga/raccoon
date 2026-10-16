import Foundation

public struct Response: Equatable, Sendable {
    public struct Header: Equatable, Sendable {
        public var name: String
        public var value: String

        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    public var status: Int
    /// In wire order, duplicates kept.
    public var headers: [Header]
    public var body: Data
    public var elapsed: Duration
    public var byteCount: Int

    public init(status: Int, headers: [Header], body: Data, elapsed: Duration, byteCount: Int) {
        self.status = status
        self.headers = headers
        self.body = body
        self.elapsed = elapsed
        self.byteCount = byteCount
    }
}

/// Cancelling a send returns to `.idle`; it is not a failure.
public enum ResponseState: Equatable, Sendable {
    case idle
    case sending(since: ContinuousClock.Instant)
    case received(Response)
    case failed(SendError)
    /// Resolution failed, so no byte went out.
    case notSent(ResolveError)
}

extension ResponseState {
    /// A send shows its spinner only once it has run 150 ms, so a fast local API never flashes one.
    public func showsSpinner(at now: ContinuousClock.Instant) -> Bool {
        guard case .sending(let since) = self else { return false }
        return now - since >= .milliseconds(150)
    }
}
