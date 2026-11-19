import Foundation
import RaccoonDomain
import Testing

struct ExampleFromResponseTests {
    let id = ExampleID(UUID(uuidString: "00000000-0000-4000-8000-00000000E001")!)

    func response(
        status: Int = 200, headers: [Response.Header] = [], body: Data = Data(), redirects: [Redirect] = []
    ) -> Response {
        Response(status: status, headers: headers, body: body, elapsed: .milliseconds(88), byteCount: body.count,
                 url: URL(string: "https://api.test/final"), method: "GET", redirects: redirects)
    }

    @Test func `a gzip Response loses the four framing headers and keeps the rest in order`() {
        let gzip = response(
            headers: [
                .init(name: "Connection", value: "keep-alive"),
                .init(name: "Content-Encoding", value: "gzip"),
                .init(name: "Content-Length", value: "20"),
                .init(name: "Content-Type", value: "application/json"),
                .init(name: "Transfer-Encoding", value: "chunked"),
                .init(name: "X-Request-Id", value: "abc"),
            ],
            body: Data(#"{"ok":true}"#.utf8))

        let example = Example.from(gzip, id: id)

        #expect(example == Example(
            id: id, name: "200 OK", status: 200,
            headers: [Row(name: "Content-Type", value: "application/json"), Row(name: "X-Request-Id", value: "abc")],
            body: .text(#"{"ok":true}"#)))
    }

    @Test(arguments: ["content-encoding", "CONTENT-LENGTH", "Transfer-encoding", "cOnNeCtIoN"])
    func `the framing headers go in any case`(name: String) {
        let example = Example.from(response(headers: [.init(name: name, value: "x"), .init(name: "Vary", value: "Accept")]), id: id)

        #expect(example.headers == [Row(name: "Vary", value: "Accept")])
    }

    @Test(arguments: [
        (200, "200 OK"), (201, "201 Created"), (404, "404 Not Found"), (503, "503 Service Unavailable"),
        (299, "299"), (599, "599"),
    ])
    func `the name is the status and its reason, and the status alone when the reason is unregistered`(status: Int, name: String) {
        let example = Example.from(response(status: status), id: id)

        #expect(example.name == name)
        #expect(example.status == status)
    }

    @Test func `a body that is not UTF-8 is kept as bytes`() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0xFF])

        #expect(Example.from(response(body: png), id: id).body == .bytes(png))
    }

    @Test func `an empty body is empty text`() {
        #expect(Example.from(response(status: 204), id: id).body == .text(""))
    }

    @Test func `only the final Response is kept, its redirects are not`() {
        let hop = Redirect(status: 302, method: "GET", url: URL(string: "https://api.test/a")!, location: URL(string: "https://api.test/final")!,
                           headers: [.init(name: "Location", value: "https://api.test/final")])
        let example = Example.from(response(headers: [.init(name: "X-Final", value: "1")], redirects: [hop]), id: id)

        #expect(example.headers == [Row(name: "X-Final", value: "1")])
    }

    @Test func `the delay is none`() {
        #expect(Example.from(response(), id: id).delayMilliseconds == 0)
    }
}
