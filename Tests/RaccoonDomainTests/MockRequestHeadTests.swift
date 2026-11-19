import Foundation
import RaccoonDomain
import Testing

struct MockRequestHeadTests {
    private func parse(_ text: String) -> MockRequestHead.Outcome {
        MockRequestHead.parse(Data(text.utf8))
    }

    private func head(_ outcome: MockRequestHead.Outcome) throws -> (MockRequestHead, consumed: Int, bodyRemaining: Int) {
        guard case let .head(head, consumed, bodyRemaining) = outcome else {
            Issue.record("expected a head, got \(outcome)")
            throw CancellationError()
        }
        return (head, consumed, bodyRemaining)
    }

    @Test(arguments: [
        "",
        "GET /users HTTP/1.1",
        "GET /users HTTP/1.1\r\n",
        "GET /users HTTP/1.1\r\nHost: x\r\n",
        "GET /users HTTP/1.1\r\nHost: x\r\n\r",
    ])
    func `a partial head needs more bytes`(text: String) {
        #expect(parse(text) == .needMore)
    }

    @Test func `a head reports the bytes it consumed and the body still to drain`() throws {
        let text = "POST /a HTTP/1.1\r\nContent-Length: 10\r\n\r\n"
        let (parsed, consumed, remaining) = try head(parse(text))
        #expect(parsed.bodyLength == 10)
        #expect(consumed == text.utf8.count)
        #expect(remaining == 10)
    }

    @Test(arguments: [0, 4, 10, 12])
    func `body bytes already in the input are consumed, the rest is left to drain`(extra: Int) throws {
        // `extra` bytes follow a head declaring Content-Length 10.
        let text = "PUT /a HTTP/1.1\r\nContent-Length: 10\r\n\r\n" + String(repeating: "x", count: extra)
        let headLength = text.utf8.count - extra
        let (_, consumed, remaining) = try head(parse(text))
        #expect(consumed == headLength + min(extra, 10))
        #expect(remaining == 10 - min(extra, 10))
    }

    @Test func `no Content-Length means no body`() throws {
        let (parsed, consumed, remaining) = try head(parse("GET /a HTTP/1.1\r\nHost: x\r\n\r\n"))
        #expect(parsed.bodyLength == 0)
        #expect(consumed == "GET /a HTTP/1.1\r\nHost: x\r\n\r\n".utf8.count)
        #expect(remaining == 0)
    }

    @Test func `headers keep their order, their case and trimmed values`() throws {
        let (parsed, _, _) = try head(parse("GET / HTTP/1.1\r\nHost:  x \r\naccept: a/b\r\nX-Dup: 1\r\nX-Dup:\t2\r\n\r\n"))
        #expect(parsed.method == "GET")
        #expect(parsed.headers == [
            .init(name: "Host", value: "x"), .init(name: "accept", value: "a/b"),
            .init(name: "X-Dup", value: "1"), .init(name: "X-Dup", value: "2"),
        ])
    }

    @Test(arguments: [
        ("/", []),
        ("/users", ["users"]),
        ("/users/", ["users"]),
        ("/users/42?x=1&y=/z", ["users", "42"]),
        ("/users?", ["users"]),
        ("/a%20b/c%2Fd/%C3%A9", ["a b", "c/d", "é"]),
        ("/a+b", ["a+b"]),
        ("/a//b", ["a", "", "b"]),
    ])
    func `the path drops the query and is percent-decoded per segment`(target: String, segments: [String]) throws {
        let (parsed, _, _) = try head(parse("GET \(target) HTTP/1.1\r\n\r\n"))
        #expect(parsed.path == segments)
    }

    @Test(arguments: [
        "\r\n\r\n",
        "GET\r\n\r\n",
        "GET /a\r\n\r\n",
        "GET  /a HTTP/1.1\r\n\r\n",
        "GET /a HTTP/1.1 x\r\n\r\n",
        "GET /a HTTP/2\r\n\r\n",
        "GET /a HTTPS/1.1\r\n\r\n",
        "G(T /a HTTP/1.1\r\n\r\n",
        "GET a HTTP/1.1\r\n\r\n",
        "GET /%zz HTTP/1.1\r\n\r\n",
        "GET /%FF HTTP/1.1\r\n\r\n",
        "GET /a HTTP/1.1\r\nNoColon\r\n\r\n",
        "GET /a HTTP/1.1\r\n: v\r\n\r\n",
        "GET /a HTTP/1.1\r\nBad Name: v\r\n\r\n",
        "GET /a HTTP/1.1\r\nA: 1\n\r\n\r\n",
        "GET /a HTTP/1.1\n\n",
        "GET /a HTTP/1.1\nHost: x\n\n",
        "GET /a\nHTTP/1.1\r\n",
        "GET /a HTTP/1.1\r\nHost: x\n",
        "GET /a HTTP/1.1\r\nContent-Length: -1\r\n\r\n",
        "GET /a HTTP/1.1\r\nContent-Length: 1x\r\n\r\n",
        "GET /a HTTP/1.1\r\nContent-Length: \r\n\r\n",
        "GET /a HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n",
    ])
    func `a malformed head is a 400`(text: String) {
        guard case let .failure(status, reason) = parse(text) else {
            Issue.record("expected a failure for \(text.debugDescription), got \(parse(text))")
            return
        }
        #expect(status == 400)
        #expect(!reason.isEmpty)
    }

    @Test(arguments: [
        "GET /a HTTP/1.1\r\nHost: x\r\n folded\r\n\r\n",
        "GET /a HTTP/1.1\r\nHost: x\r\n\tfolded\r\n\r\n",
        "GET /a HTTP/1.1\r\n Host: x\r\n\r\n",
    ])
    func `header folding is not accepted`(text: String) {
        guard case let .failure(status, reason) = parse(text) else {
            Issue.record("expected a failure, got \(parse(text))")
            return
        }
        #expect(status == 400)
        #expect(reason.contains("fold"))
    }

    @Test func `identical duplicate Content-Length headers are one length`() throws {
        let (parsed, _, _) = try head(parse("POST /a HTTP/1.1\r\ncontent-length: 5\r\nContent-Length: 5\r\n\r\n"))
        #expect(parsed.bodyLength == 5)
    }

    @Test(arguments: ["Transfer-Encoding: chunked", "transfer-encoding: gzip, chunked", "TRANSFER-ENCODING: x"])
    func `Transfer-Encoding on the request is a 501`(header: String) {
        guard case let .failure(status, _) = parse("POST /a HTTP/1.1\r\n\(header)\r\n\r\n") else {
            Issue.record("expected a failure")
            return
        }
        #expect(status == 501)
    }

    @Test func `a head over 64 KiB is a 413 whether or not it is finished`() {
        let big = "GET /a HTTP/1.1\r\nX: " + String(repeating: "a", count: 64 * 1024)
        // unfinished: no terminator yet, already too long
        guard case let .failure(status, _) = parse(big) else {
            Issue.record("expected a failure for an unfinished oversize head")
            return
        }
        #expect(status == 413)
        // finished
        guard case let .failure(finishedStatus, _) = parse(big + "\r\n\r\n") else {
            Issue.record("expected a failure for a finished oversize head")
            return
        }
        #expect(finishedStatus == 413)
    }

    @Test func `a head of exactly 64 KiB parses, one byte more is a 413`() throws {
        let prefix = "GET /a HTTP/1.1\r\nX: "
        let suffix = "\r\n\r\n"
        let fill = 64 * 1024 - prefix.utf8.count - suffix.utf8.count
        let exact = prefix + String(repeating: "a", count: fill) + suffix
        #expect(exact.utf8.count == 64 * 1024)
        _ = try head(parse(exact))
        guard case let .failure(status, _) = parse(prefix + String(repeating: "a", count: fill + 1) + suffix) else {
            Issue.record("expected a failure")
            return
        }
        #expect(status == 413)
    }

    @Test func `a body over 16 MiB is a 413, 16 MiB is accepted`() throws {
        let limit = 16 * 1024 * 1024
        let (parsed, _, remaining) = try head(parse("POST /a HTTP/1.1\r\nContent-Length: \(limit)\r\n\r\n"))
        #expect(parsed.bodyLength == limit)
        #expect(remaining == limit)
        for length in ["\(limit + 1)", "99999999999999999999999999"] {
            guard case let .failure(status, _) = parse("POST /a HTTP/1.1\r\nContent-Length: \(length)\r\n\r\n") else {
                Issue.record("expected a failure for \(length)")
                continue
            }
            #expect(status == 413)
        }
    }
}
