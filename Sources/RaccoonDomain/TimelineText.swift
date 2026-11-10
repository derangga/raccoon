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
        /// left out when unknown, never guessed. Later lines (phases, connection) add fields here.
        public var fields: [String]
        /// Two columns under the first line: a Redirect's Location, then its headers.
        public var rows: [Response.Header]

        public init(code: String, reason: String, token: ColorToken, fields: [String], rows: [Response.Header]) {
            self.code = code
            self.reason = reason
            self.token = token
            self.fields = fields
            self.rows = rows
        }

        /// "302 Found", the part drawn in the status color.
        public var statusText: String { reason.isEmpty ? code : "\(code) \(reason)" }

        /// "302 Found · GET · https://a.example/login".
        public var line: String { ([statusText] + fields).joined(separator: " · ") }
    }

    public static let headersNote = "macOS merges repeated headers and doesn't keep their order."

    /// The Response's own headers are not repeated: they are in Headers.
    public static func blocks(_ response: Response) -> [Block] {
        let redirects = response.redirects.map { redirect in
            block(status: redirect.status, method: redirect.method, url: redirect.url,
                  rows: [.init(name: "Location", value: redirect.location.absoluteString)] + redirect.headers)
        }
        return redirects + [block(status: response.status, method: response.method, url: response.url, rows: [])]
    }

    /// Only a Redirect's headers are drawn here, so only they need the note.
    public static func showsHeadersNote(_ response: Response) -> Bool {
        response.redirects.contains { !$0.headers.isEmpty }
    }

    private static func block(status: Int, method: String?, url: URL?, rows: [Response.Header]) -> Block {
        let line = StatusLine(status: status, elapsed: .zero, byteCount: 0)
        return Block(code: line.code, reason: line.reason, token: line.token,
                     fields: [method, url?.absoluteString].compactMap { $0 }, rows: rows)
    }
}
