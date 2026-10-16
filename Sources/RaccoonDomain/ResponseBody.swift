import Foundation

/// What the Response viewer draws for a body.
public enum ResponseBody: Equatable, Sendable {
    /// Formatted text, colored by `Highlighter.ranges(text, kind:)`.
    case pretty(String, RawKind)
    case raw(String)
    case binary(byteCount: Int)

    /// Above this many bytes the body is shown Raw (environment-facts.md, NSTextView).
    public static let prettyThreshold = 5_000_000

    /// Pretty is decided by parsing, not by `Content-Type`, which only picks the parser tried
    /// first. A body that does not parse is Raw, never an error.
    public static func presentation(_ response: Response) -> ResponseBody {
        guard let text = String(validating: response.body, as: UTF8.self) else {
            return .binary(byteCount: response.byteCount)
        }
        guard response.byteCount <= prettyThreshold else { return .raw(text) }
        let contentType = response.headers.first { $0.name.lowercased() == "content-type" }?.value ?? ""
        let kinds: [RawKind] = contentType.lowercased().contains("xml") ? [.xml, .json] : [.json, .xml]
        for kind in kinds {
            // The XML formatter takes tagless text as one text node, so XML must open with a tag.
            if kind == .xml, text.drop(while: \.isWhitespace).first != "<" { continue }
            if let formatted = try? BodyFormatter.format(text, kind: kind) { return .pretty(formatted, kind) }
        }
        return .raw(text)
    }
}

/// The status line's text, ready to draw.
public struct StatusLine: Equatable, Sendable {
    public var code: String
    /// Empty for a code with no registered reason.
    public var reason: String
    public var token: ColorToken
    public var elapsed: String
    public var size: String

    public init(status: Int, elapsed: Duration, byteCount: Int) {
        code = "\(status)"
        reason = Self.reasons[status] ?? ""
        token = switch status {
        case ..<200: .status1xx
        case ..<300: .status2xx
        case ..<400: .status3xx
        case ..<500: .status4xx
        default: .status5xx
        }
        let ms = Int(elapsed / .milliseconds(1))
        self.elapsed = ms < 1_000 ? "\(ms) ms" : Self.oneDecimal(Double(ms) / 1_000) + " s"
        size = Self.size(byteCount)
    }

    private static func size(_ bytes: Int) -> String {
        if bytes < 1_000 { return "\(bytes) B" }
        var value = Double(bytes) / 1_000
        for unit in ["KB", "MB"] {
            if value < 1_000 { return oneDecimal(value) + " " + unit }
            value /= 1_000
        }
        return oneDecimal(value) + " GB"
    }

    /// Fixed to "." so the status line reads the same in every locale.
    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// The IANA HTTP status code registry.
    private static let reasons: [Int: String] = [
        100: "Continue", 101: "Switching Protocols", 102: "Processing", 103: "Early Hints",
        200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information",
        204: "No Content", 205: "Reset Content", 206: "Partial Content", 207: "Multi-Status",
        208: "Already Reported", 226: "IM Used",
        300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other",
        304: "Not Modified", 305: "Use Proxy", 307: "Temporary Redirect", 308: "Permanent Redirect",
        400: "Bad Request", 401: "Unauthorized", 402: "Payment Required", 403: "Forbidden",
        404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable",
        407: "Proxy Authentication Required", 408: "Request Timeout", 409: "Conflict", 410: "Gone",
        411: "Length Required", 412: "Precondition Failed", 413: "Content Too Large",
        414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable",
        417: "Expectation Failed", 421: "Misdirected Request", 422: "Unprocessable Content",
        423: "Locked", 424: "Failed Dependency", 425: "Too Early", 426: "Upgrade Required",
        428: "Precondition Required", 429: "Too Many Requests",
        431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons",
        500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway",
        503: "Service Unavailable", 504: "Gateway Timeout", 505: "HTTP Version Not Supported",
        506: "Variant Also Negotiates", 507: "Insufficient Storage", 508: "Loop Detected",
        510: "Not Extended", 511: "Network Authentication Required",
    ]
}
