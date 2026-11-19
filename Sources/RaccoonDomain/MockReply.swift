import Foundation

/// What the Mock Server answers one request with, before framing.
public struct MockReply: Equatable, Sendable {
    public var status: Int
    public var headers: [Response.Header]
    public var body: Data
    public var delay: Duration

    public init(status: Int, headers: [Response.Header], body: Data, delay: Duration) {
        self.status = status
        self.headers = headers
        self.body = body
        self.delay = delay
    }

    /// HTTP/1.1 bytes: the headers in their order, then the framing ones. A `Content-Length` or
    /// `Connection` the reply holds is dropped: the computed ones replace it.
    public static func bytes(_ reply: MockReply) -> Data {
        var head = "HTTP/1.1 \(reply.status) \(reasons[reply.status] ?? "")\r\n"
        // shortcut: header values are written as they are, so a CR or LF in one splits the reply; sanitise when Examples can come from outside the Data Folder
        for header in reply.headers where !["content-length", "connection"].contains(header.name.lowercased()) {
            head += "\(header.name): \(header.value)\r\n"
        }
        head += "Content-Length: \(reply.body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + reply.body
    }

    private static let reasons: [Int: String] = [
        100: "Continue", 101: "Switching Protocols", 102: "Processing", 103: "Early Hints",
        200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content",
        205: "Reset Content", 206: "Partial Content", 207: "Multi-Status", 208: "Already Reported", 226: "IM Used",
        300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified",
        305: "Use Proxy", 307: "Temporary Redirect", 308: "Permanent Redirect",
        400: "Bad Request", 401: "Unauthorized", 402: "Payment Required", 403: "Forbidden", 404: "Not Found",
        405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required",
        408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed",
        413: "Content Too Large", 414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable",
        417: "Expectation Failed", 418: "I'm a teapot", 421: "Misdirected Request", 422: "Unprocessable Content",
        423: "Locked", 424: "Failed Dependency", 425: "Too Early", 426: "Upgrade Required",
        428: "Precondition Required", 429: "Too Many Requests", 431: "Request Header Fields Too Large",
        451: "Unavailable For Legal Reasons",
        500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable",
        504: "Gateway Timeout", 505: "HTTP Version Not Supported", 506: "Variant Also Negotiates",
        507: "Insufficient Storage", 508: "Loop Detected", 510: "Not Extended", 511: "Network Authentication Required",
    ]
}
