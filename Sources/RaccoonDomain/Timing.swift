import Foundation

/// How long one request of a send spent in each phase, as URLSession measured it. A phase that
/// did not happen, or whose marks were unusable, is nil: absent, never 0.
public struct Timing: Equatable, Sendable {
    public var dns: Duration?
    public var connect: Duration?
    public var tls: Duration?
    public var send: Duration?
    public var waiting: Duration?
    public var download: Duration?
    public var total: Duration?
    public var reusedConnection: Bool
    /// "h2", "http/1.1", as URLSession names it.
    public var protocolName: String?
    /// "93.184.216.34:443": the port is included when known.
    public var remoteAddress: String?
    /// "TLS 1.3"; nil over plain HTTP.
    public var tlsVersion: String?
    /// The Wire Size: the body's bytes as they crossed the network, before `Content-Encoding` was undone.
    public var bodyBytesOnWire: Int?

    public init(
        dns: Duration? = nil, connect: Duration? = nil, tls: Duration? = nil, send: Duration? = nil,
        waiting: Duration? = nil, download: Duration? = nil, total: Duration? = nil, reusedConnection: Bool = false,
        protocolName: String? = nil, remoteAddress: String? = nil, tlsVersion: String? = nil, bodyBytesOnWire: Int? = nil
    ) {
        self.dns = dns
        self.connect = connect
        self.tls = tls
        self.send = send
        self.waiting = waiting
        self.download = download
        self.total = total
        self.reusedConnection = reusedConnection
        self.protocolName = protocolName
        self.remoteAddress = remoteAddress
        self.tlsVersion = tlsVersion
        self.bodyBytesOnWire = bodyBytesOnWire
    }

    /// One transaction's dates and counts, copied as they are, so the rule below needs no URLSession.
    public struct Marks: Equatable, Sendable {
        public var fetchStart: Date?
        public var domainLookupStart: Date?
        public var domainLookupEnd: Date?
        public var connectStart: Date?
        public var connectEnd: Date?
        public var secureConnectionStart: Date?
        public var secureConnectionEnd: Date?
        public var requestStart: Date?
        public var requestEnd: Date?
        public var responseStart: Date?
        public var responseEnd: Date?
        public var reusedConnection = false
        public var protocolName: String?
        public var remoteAddress: String?
        public var remotePort: Int?
        /// The negotiated TLS version as its wire value: 0x0304 is TLS 1.3.
        public var tlsVersion: UInt16?
        public var bodyBytesOnWire: Int?

        public init() {}
    }

    /// Each phase is an end minus its start. The marks are wall-clock Dates, so an end before its
    /// start is possible: that phase is nil rather than negative.
    public init(_ marks: Marks) {
        func span(_ start: Date?, _ end: Date?) -> Duration? {
            guard let start, let end, end >= start else { return nil }
            // Whole microseconds: a Date near today holds about 0.2 µs of float noise, and shows nothing.
            return .microseconds(Int((end.timeIntervalSince(start) * 1e6).rounded()))
        }
        self.init(
            dns: span(marks.domainLookupStart, marks.domainLookupEnd),
            // Connect is the TCP handshake: it stops where TLS starts, and runs to connectEnd without TLS.
            connect: span(marks.connectStart, marks.secureConnectionStart ?? marks.connectEnd),
            tls: span(marks.secureConnectionStart, marks.secureConnectionEnd),
            send: span(marks.requestStart, marks.requestEnd),
            waiting: span(marks.requestEnd, marks.responseStart),
            download: span(marks.responseStart, marks.responseEnd),
            total: span(marks.fetchStart, marks.responseEnd),
            reusedConnection: marks.reusedConnection,
            protocolName: marks.protocolName,
            remoteAddress: marks.remoteAddress.map { address in
                guard let port = marks.remotePort else { return address }
                return address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
            },
            tlsVersion: marks.tlsVersion.flatMap { Self.tlsNames[$0] },
            bodyBytesOnWire: marks.bodyBytesOnWire)
    }

    private static let tlsNames: [UInt16: String] = [0x0301: "TLS 1.0", 0x0302: "TLS 1.1", 0x0303: "TLS 1.2", 0x0304: "TLS 1.3"]

    /// One Timing per request of a send, aligned from the end: URLSession keeps only the last 20
    /// transactions, so a send of 21 requests has 20 and the first has none. More timings than
    /// requests means they cannot be trusted to line up, so none is kept.
    public static func paired(_ timings: [Timing], requests: Int) -> [Timing?] {
        guard timings.count <= requests else { return Array(repeating: nil, count: requests) }
        return Array(repeating: nil, count: requests - timings.count) + timings
    }
}
