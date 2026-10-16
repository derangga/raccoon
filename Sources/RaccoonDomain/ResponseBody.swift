import Foundation

/// What the Response viewer draws for a body.
public enum ResponseBody: Equatable, Sendable {
    /// Formatted text, colored by `Highlighter.ranges(text, kind:)`.
    case pretty(String, RawKind)
    case raw(String)
    case binary(byteCount: Int)

    /// Above this many bytes the body is shown Raw. Measured: 5 MB coloured stays at or under
    /// 129 ms a step on TextKit 1 (environment-facts.md, "NSTextView with large bodies").
    public static let prettyThreshold = 5_000_000

    /// Beside the disabled Pretty segment, so the number on screen is the one in force.
    public static let prettyOffNote = "Pretty is off above \(prettyThreshold / 1_000_000) MB"

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
        self.elapsed = Self.elapsed(elapsed)
        size = Self.size(byteCount)
    }

    /// "88 ms" under a second, then "1.4 s"; also the live time while sending.
    public static func elapsed(_ duration: Duration) -> String {
        let ms = Int(duration / .milliseconds(1))
        return ms < 1_000 ? "\(ms) ms" : oneDecimal(Double(ms) / 1_000) + " s"
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

/// The failed state's text: a title, one sentence of detail, and whether the one fix applies.
public struct FailureText: Equatable, Sendable {
    public var title: String
    public var detail: String
    /// Only an untrusted certificate has a fix: turning on Allow insecure TLS.
    public var offersInsecureTLS = false

    public init(_ error: SendError) {
        switch error {
        case .timedOut:
            title = "No response after 60 s"
            detail = "The server did not answer in time. Raccoon does not send again by itself."
        case .untrustedCertificate(let host):
            title = "Untrusted certificate"
            detail = "The certificate for \(host) is not trusted by this Mac. It may be self-signed or expired."
            offersInsecureTLS = true
        case .transport(let code, let description, let host):
            title = description.hasSuffix(".") ? String(description.dropLast()) : description
            let number = code.rawValue < 0 ? "−\(-code.rawValue)" : "\(code.rawValue)"
            detail = "\(Self.names[code.rawValue] ?? "URLError") (\(number)) · \(host)"
        // The chip is marked and the message line names the path too (design-system.md §7).
        case .fileMissing(let path):
            title = "File missing"
            detail = "\(path) is missing, so nothing was sent."
        }
    }

    /// NSURLError.h, for the codes a send can end with.
    private static let names: [Int: String] = [
        -1: "NSURLErrorUnknown", -999: "NSURLErrorCancelled", -1000: "NSURLErrorBadURL",
        -1001: "NSURLErrorTimedOut", -1002: "NSURLErrorUnsupportedURL", -1003: "NSURLErrorCannotFindHost",
        -1004: "NSURLErrorCannotConnectToHost", -1005: "NSURLErrorNetworkConnectionLost",
        -1006: "NSURLErrorDNSLookupFailed", -1007: "NSURLErrorHTTPTooManyRedirects",
        -1008: "NSURLErrorResourceUnavailable", -1009: "NSURLErrorNotConnectedToInternet",
        -1010: "NSURLErrorRedirectToNonExistentLocation", -1011: "NSURLErrorBadServerResponse",
        -1012: "NSURLErrorUserCancelledAuthentication", -1013: "NSURLErrorUserAuthenticationRequired",
        -1014: "NSURLErrorZeroByteResource", -1015: "NSURLErrorCannotDecodeRawData",
        -1016: "NSURLErrorCannotDecodeContentData", -1017: "NSURLErrorCannotParseResponse",
        -1018: "NSURLErrorInternationalRoamingOff", -1019: "NSURLErrorCallIsActive",
        -1020: "NSURLErrorDataNotAllowed", -1021: "NSURLErrorRequestBodyStreamExhausted",
        -1022: "NSURLErrorAppTransportSecurityRequiresSecureConnection",
        -1100: "NSURLErrorFileDoesNotExist", -1101: "NSURLErrorFileIsDirectory",
        -1102: "NSURLErrorNoPermissionsToReadFile", -1103: "NSURLErrorDataLengthExceedsMaximum",
        -1104: "NSURLErrorFileOutsideSafeArea", -1200: "NSURLErrorSecureConnectionFailed",
        -1201: "NSURLErrorServerCertificateHasBadDate", -1202: "NSURLErrorServerCertificateUntrusted",
        -1203: "NSURLErrorServerCertificateHasUnknownRoot", -1204: "NSURLErrorServerCertificateNotYetValid",
        -1205: "NSURLErrorClientCertificateRejected", -1206: "NSURLErrorClientCertificateRequired",
        -2000: "NSURLErrorCannotLoadFromNetwork",
    ]
}
