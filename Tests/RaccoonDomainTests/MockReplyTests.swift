import Foundation
import RaccoonDomain
import Testing

struct MockReplyTests {
    private func text(_ reply: MockReply) -> String {
        String(decoding: MockReply.bytes(reply), as: UTF8.self)
    }

    @Test func `a JSON Example is framed byte for byte`() {
        let reply = MockReply(
            status: 200, headers: [.init(name: "Content-Type", value: "application/json")],
            body: Data(#"{"ok":true}"#.utf8), delay: .zero)
        #expect(
            MockReply.bytes(reply)
                == Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 11\r\nConnection: close\r\n\r\n{\"ok\":true}".utf8))
    }

    @Test func `an Example's own Content-Length and Connection are replaced, not doubled`() {
        let reply = MockReply(
            status: 201,
            headers: [
                .init(name: "X-A", value: "1"), .init(name: "content-length", value: "999"),
                .init(name: "X-B", value: "2"), .init(name: "CONNECTION", value: "keep-alive"),
                .init(name: "X-A", value: "3"),
            ],
            body: Data("hi".utf8), delay: .milliseconds(5))
        #expect(text(reply) == "HTTP/1.1 201 Created\r\nX-A: 1\r\nX-B: 2\r\nX-A: 3\r\nContent-Length: 2\r\nConnection: close\r\n\r\nhi")
    }

    @Test func `an empty body still carries Content-Length 0`() {
        let reply = MockReply(status: 204, headers: [], body: Data(), delay: .zero)
        #expect(text(reply) == "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    }

    @Test func `Content-Length counts bytes, not characters`() {
        let reply = MockReply(status: 200, headers: [], body: Data("é€".utf8), delay: .zero)
        #expect(text(reply).contains("Content-Length: 5\r\n"))
    }

    @Test(arguments: [
        (100, "Continue"), (200, "OK"), (301, "Moved Permanently"), (404, "Not Found"),
        (413, "Content Too Large"), (418, "I'm a teapot"), (500, "Internal Server Error"), (501, "Not Implemented"),
        (299, ""),
    ])
    func `the status line carries the standard reason phrase`(status: Int, phrase: String) {
        let reply = MockReply(status: status, headers: [], body: Data(), delay: .zero)
        #expect(text(reply).hasPrefix("HTTP/1.1 \(status) \(phrase)\r\n"))
    }
}
