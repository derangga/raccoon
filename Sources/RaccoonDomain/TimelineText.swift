import Foundation

/// Every string the Response viewer's Timeline draws: one Block per Redirect, then one for the
/// Response, in the order they were sent.
public enum TimelineText {
    public struct Block: Equatable, Sendable {
        /// The status, drawn in `token`'s color.
        public var code: String
        /// Empty for a code with no registered reason.
        public var reason: String
        public var token: ColorToken
        /// What follows the status on the first line, in the text color: method, URL. Each is
        /// left out when unknown, never guessed; the request's total comes last.
        public var fields: [String]
        /// Two columns under the first line: a Redirect's Location, then its headers.
        public var rows: [Response.Header]
        /// "DNS 4 ms · Connect 12 ms · …", or the not-reported sentence. Nil: nothing to say.
        public var phases: String?
        /// "h2 · 93.184.216.34:443 · TLS 1.3". Nil when nothing is known.
        public var connection: String?
        /// "1.2 KB · 420 B on the wire": the Response's block, when the Wire Size differs.
        public var size: String?

        public init(
            code: String, reason: String, token: ColorToken, fields: [String], rows: [Response.Header],
            phases: String? = nil, connection: String? = nil, size: String? = nil
        ) {
            self.code = code
            self.reason = reason
            self.token = token
            self.fields = fields
            self.rows = rows
            self.phases = phases
            self.connection = connection
            self.size = size
        }

        /// "302 Found", the part drawn in the status color.
        public var statusText: String { reason.isEmpty ? code : "\(code) \(reason)" }

        /// "302 Found · GET · https://a.example/login".
        public var line: String { ([statusText] + fields).joined(separator: " · ") }
    }

    public static let notReported = "Timing was not reported for this send."

    public static let headersNote = "macOS merges repeated headers and doesn't keep their order."

    /// The Response's own headers are not repeated: they are in Headers.
    public static func blocks(_ response: Response) -> [Block] {
        let reported = response.redirects.contains { $0.timing != nil } || response.timing != nil
        let redirects = response.redirects.map { redirect in
            block(status: redirect.status, method: redirect.method, url: redirect.url, timing: redirect.timing,
                  reported: reported, rows: [.init(name: "Location", value: redirect.location.absoluteString)] + redirect.headers)
        }
        let size = response.timing?.bodyBytesOnWire.flatMap { wire in
            wire == response.byteCount ? nil : "\(bytes(response.byteCount)) · \(bytes(wire)) on the wire"
        }
        return redirects + [block(status: response.status, method: response.method, url: response.url, timing: response.timing,
                                  reported: reported, rows: [], size: size)]
    }

    /// Only a Redirect's headers are drawn here, so only they need the note.
    public static func showsHeadersNote(_ response: Response) -> Bool {
        response.redirects.contains { !$0.headers.isEmpty }
    }

    private static func block(
        status: Int, method: String?, url: URL?, timing: Timing?, reported: Bool, rows: [Response.Header], size: String? = nil
    ) -> Block {
        let line = StatusLine(status: status, elapsed: .zero, byteCount: 0)
        return Block(code: line.code, reason: line.reason, token: line.token,
                     fields: [method, url?.absoluteString, timing?.total.map(StatusLine.elapsed)].compactMap { $0 }, rows: rows,
                     phases: timing.flatMap(phases) ?? (reported ? nil : notReported), connection: timing.flatMap(connection),
                     size: size)
    }

    /// Reused connection stands in for the three phases a kept-alive connection skipped.
    private static func phases(_ timing: Timing) -> String? {
        let first: [(String, Duration?)] = timing.reusedConnection ? [] : [("DNS", timing.dns), ("Connect", timing.connect), ("TLS", timing.tls)]
        let rest: [(String, Duration?)] = [("Send", timing.send), ("Waiting", timing.waiting), ("Download", timing.download)]
        let parts = (timing.reusedConnection ? ["Reused connection"] : []) + (first + rest).compactMap { name, time in
            time.map { "\(name) \(StatusLine.elapsed($0))" }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func connection(_ timing: Timing) -> String? {
        let parts = [timing.protocolName, timing.remoteAddress, timing.tlsVersion].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// StatusLine's size words: "420 B", "1.2 KB".
    private static func bytes(_ count: Int) -> String {
        StatusLine(status: 200, elapsed: .zero, byteCount: count).size
    }
}
