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
    /// Sorted by name: URLSession joins duplicates with ", " and loses wire order (environment-facts.md).
    public var headers: [Header]
    public var body: Data
    public var elapsed: Duration
    public var byteCount: Int
    /// The URL that produced this Response: the last one, when the send followed redirects.
    public var url: URL?
    /// The method of the request that got this Response: the original, or what the last followed
    /// redirect sent. Nil for a Response nobody sent, such as a scripted one.
    public var method: String?
    /// In the order they were followed; empty when the send was not redirected.
    public var redirects: [Redirect]

    public init(
        status: Int, headers: [Header], body: Data, elapsed: Duration, byteCount: Int,
        url: URL? = nil, method: String? = nil, redirects: [Redirect] = []
    ) {
        self.status = status
        self.headers = headers
        self.body = body
        self.elapsed = elapsed
        self.byteCount = byteCount
        self.url = url
        self.method = method
        self.redirects = redirects
    }
}

/// Cancelling a send returns to `.idle`; it is not a failure.
public enum ResponseState: Equatable, Sendable {
    case idle
    case sending(since: ContinuousClock.Instant)
    case received(Response)
    /// `after` is how long the send ran, for the status line's "after 212 ms".
    case failed(SendError, after: Duration)
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
