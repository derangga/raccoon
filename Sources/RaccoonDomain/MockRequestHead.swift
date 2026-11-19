import Foundation

/// What `parse` read off a Mock Server connection: the request line and headers. The body is
/// counted, never kept.
public struct MockRequestHead: Equatable, Sendable {
    public var method: String
    /// The URL path without its query, split on `/`, each segment percent-decoded (so a `%2F`
    /// stays inside its segment). A trailing `/` adds no segment; an empty segment in the
    /// middle stays, and matches no wildcard.
    public var path: [String]
    /// In wire order, names as sent, values trimmed.
    public var headers: [Response.Header]
    /// Content-Length, or 0.
    public var bodyLength: Int

    public init(method: String, path: [String], headers: [Response.Header], bodyLength: Int) {
        self.method = method
        self.path = path
        self.headers = headers
        self.bodyLength = bodyLength
    }

    public enum Outcome: Equatable, Sendable {
        /// The head is not finished: call `parse` again with more bytes.
        case needMore
        /// `consumed` is the bytes of the input to drop: the head plus whatever of the body the
        /// input already holds. `bodyRemaining` is what the socket must still be read and dropped
        /// for. One request per connection, so bytes past the body are ignored.
        case head(MockRequestHead, consumed: Int, bodyRemaining: Int)
        /// Answer `status` (400, 413 or 501), then close.
        case failure(status: Int, reason: String)
    }

    static let maxHead = 64 * 1024
    static let maxBody = 16 * 1024 * 1024

    private struct Failure: Error {
        var status: Int
        var reason: String
    }

    public static func parse(_ bytes: Data) -> Outcome {
        let window = Data(bytes.prefix(maxHead))
        let end = window.range(of: Data("\r\n\r\n".utf8))
        // A bare LF can never be part of a CRLF-terminated head: say so now, not at 64 KiB.
        let lines = end.map { window.prefix($0.lowerBound) } ?? window
        if lines.indices.contains(where: { lines[$0] == 10 && ($0 == 0 || lines[$0 - 1] != 13) }) {
            return .failure(status: 400, reason: "bare LF in the head")
        }
        guard let end else {
            return bytes.count > maxHead ? .failure(status: 413, reason: "request head over 64 KiB") : .needMore
        }
        do throws(Failure) {
            let text = String(decoding: window.prefix(end.lowerBound), as: UTF8.self)
            let (method, target, headers) = try split(text)
            try rejectTransferEncoding(headers)
            let bodyLength = try contentLength(headers)
            let path = try segments(of: target)
            let headLength = end.upperBound
            let present = min(bytes.count - headLength, bodyLength)
            let head = MockRequestHead(method: method, path: path, headers: headers, bodyLength: bodyLength)
            return .head(head, consumed: headLength + present, bodyRemaining: bodyLength - present)
        } catch {
            return .failure(status: error.status, reason: error.reason)
        }
    }

    private static func split(_ text: String) throws(Failure) -> (method: String, target: String, headers: [Response.Header]) {
        let lines = text.components(separatedBy: "\r\n")
        guard !lines.contains(where: { $0.unicodeScalars.contains { $0 == "\r" || $0 == "\n" } }) else {
            throw Failure(status: 400, reason: "bare CR or LF in the head")
        }
        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[0].isEmpty, parts[0].allSatisfy({ $0.isASCII && $0.isLetter }),
            parts[1].hasPrefix("/"), parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0"
        else { throw Failure(status: 400, reason: "malformed request line") }
        var headers: [Response.Header] = []
        for line in lines.dropFirst() {
            guard line.first != " ", line.first != "\t" else {
                throw Failure(status: 400, reason: "header folding is not accepted")
            }
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex,
                line[..<colon].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "!#$%&'*+-.^_`|~".contains($0)) })
            else { throw Failure(status: 400, reason: "malformed header line") }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: [" ", "\t"])
            headers.append(.init(name: String(line[..<colon]), value: value))
        }
        return (String(parts[0]), String(parts[1]), headers)
    }

    private static func rejectTransferEncoding(_ headers: [Response.Header]) throws(Failure) {
        // shortcut: chunked request bodies are not read, upgrade when a client needs it
        if headers.contains(where: { $0.name.lowercased() == "transfer-encoding" }) {
            throw Failure(status: 501, reason: "Transfer-Encoding on a request is not supported")
        }
    }

    private static func contentLength(_ headers: [Response.Header]) throws(Failure) -> Int {
        let values = Set(headers.filter { $0.name.lowercased() == "content-length" }.map(\.value))
        guard let value = values.first else { return 0 }
        guard values.count == 1, !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw Failure(status: 400, reason: "bad Content-Length")
        }
        // all digits but too many for an Int is simply too big
        guard let length = Int(value), length <= maxBody else {
            throw Failure(status: 413, reason: "request body over 16 MiB")
        }
        return length
    }

    private static func segments(of target: String) throws(Failure) -> [String] {
        var raw = target.prefix { $0 != "?" }.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        while raw.last?.isEmpty == true { raw.removeLast() }
        var decoded: [String] = []
        for segment in raw {
            guard let text = String(segment).removingPercentEncoding else {
                throw Failure(status: 400, reason: "bad percent-encoding in the path")
            }
            decoded.append(text)
        }
        return decoded
    }
}
