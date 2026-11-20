import Foundation
import RaccoonDomain
import Testing

/// Answering one request from the routes (mock-server.md §Answer a request, §Matching).
struct MockMatchTests {
    private func example(
        _ name: String, _ status: Int = 200, headers: [Row] = [], body: String = "", delay: Int = 0
    ) -> Example {
        Example(
            id: ExampleID(UUID()), name: name, status: status, headers: headers,
            body: .text(body), delayMilliseconds: delay)
    }

    private func route(_ method: String, _ segments: [MockSegment], _ examples: [Example]) -> MockRoute {
        MockRoute(method: method, segments: segments, requestName: "r", examples: examples)
    }

    private func head(_ path: [String], _ headers: [(String, String)] = []) -> MockRequestHead {
        head("GET", path, headers)
    }

    private func head(_ method: String, _ path: [String], _ headers: [(String, String)] = []) -> MockRequestHead {
        MockRequestHead(
            method: method, path: path, headers: headers.map { .init(name: $0.0, value: $0.1) }, bodyLength: 0)
    }

    private func body(_ reply: MockReply) -> String { String(decoding: reply.body, as: UTF8.self) }

    private func value(_ reply: MockReply, _ name: String) -> String? {
        reply.headers.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    // MARK: matching

    @Test func `a literal route beats a wildcard one whichever comes first`() {
        let wild = route("GET", [.literal("users"), .wildcard], [example("wild", 201)])
        let me = route("GET", [.literal("users"), .literal("me")], [example("me", 202)])

        #expect(MockMatch.answer([wild, me], head(["users", "me"]), allowsCORS: false).status == 202)
        #expect(MockMatch.answer([me, wild], head(["users", "me"]), allowsCORS: false).status == 202)
        #expect(MockMatch.answer([me, wild], head(["users", "42"]), allowsCORS: false).status == 201)
    }

    @Test func `the first difference from the left decides, not the count of literals`() {
        let leftWild = route("GET", [.wildcard, .literal("b"), .literal("c")], [example("x", 201)])
        let rightWild = route("GET", [.literal("a"), .wildcard, .wildcard], [example("y", 202)])

        #expect(MockMatch.answer([leftWild, rightWild], head(["a", "b", "c"]), allowsCORS: false).status == 202)
    }

    @Test func `two routes of one shape: the first in sidebar order answers`() {
        let first = route("GET", [.literal("a"), .wildcard], [example("first", 201)])
        let second = route("GET", [.literal("a"), .wildcard], [example("second", 202)])

        #expect(MockMatch.answer([first, second], head(["a", "x"]), allowsCORS: false).status == 201)
    }

    @Test func `a method mismatch is not a candidate`() {
        let post = route("POST", [.literal("users")], [example("ok")])

        let reply = MockMatch.answer([post], head("GET", ["users"]), allowsCORS: false)

        #expect(reply.status == 404)
        #expect(body(reply) == #"{"error":"No Example matches GET /users"}"#)
    }

    @Test func `a segment count mismatch is not a candidate`() {
        let users = route("GET", [.literal("users"), .wildcard], [example("ok")])

        #expect(MockMatch.answer([users], head(["users"]), allowsCORS: false).status == 404)
        #expect(MockMatch.answer([users], head(["users", "1", "x"]), allowsCORS: false).status == 404)
    }

    @Test func `a literal is case-sensitive and compared to the decoded segment`() {
        let space = route("GET", [.literal("a b")], [example("ok")])

        #expect(MockMatch.answer([space], head(["a b"]), allowsCORS: false).status == 200)
        #expect(MockMatch.answer([space], head(["A b"]), allowsCORS: false).status == 404)
        #expect(MockMatch.answer([space], head(["a%20b"]), allowsCORS: false).status == 404)
    }

    @Test func `a wildcard matches any one non-empty segment`() {
        let any = route("GET", [.literal("users"), .wildcard], [example("ok")])

        #expect(MockMatch.answer([any], head(["users", "a b"]), allowsCORS: false).status == 200)
        #expect(MockMatch.answer([any], head(["users", ""]), allowsCORS: false).status == 404)
    }

    @Test func `the root path matches a route of no segments`() {
        let root = route("GET", [], [example("ok")])

        #expect(MockMatch.answer([root], head([]), allowsCORS: false).status == 200)
    }

    // MARK: the pick

    private var named: [Example] { [example("ok", 200, body: "a"), example("missing", 404, body: "b"), example("also ok", 200, body: "c")] }

    @Test func `no header: the first Example answers`() {
        let reply = MockMatch.answer([route("GET", [.literal("a")], named)], head(["a"]), allowsCORS: false)

        #expect(body(reply) == "a")
    }

    @Test func `x-mock-response-name picks the first Example of that name, in any header case`() {
        let dup = [example("x", 200, body: "1"), example("y", 201, body: "2"), example("y", 202, body: "3")]
        let reply = MockMatch.answer(
            [route("GET", [.literal("a")], dup)], head(["a"], [("X-Mock-Response-NAME", "y")]), allowsCORS: false)

        #expect(body(reply) == "2")
    }

    @Test func `x-mock-response-code picks the first Example with that status`() {
        let reply = MockMatch.answer(
            [route("GET", [.literal("a")], named)], head(["a"], [("x-mock-response-code", "200")]), allowsCORS: false)
        let second = MockMatch.answer(
            [route("GET", [.literal("a")], named)], head(["a"], [("X-Mock-Response-Code", " 404 ")]), allowsCORS: false)

        #expect(body(reply) == "a")
        #expect(body(second) == "b")
    }

    @Test func `both headers: the Example of that name with that status wins`() {
        let examples = [example("n", 200, body: "1"), example("n", 500, body: "2"), example("m", 500, body: "3")]
        let reply = MockMatch.answer(
            [route("GET", [.literal("a")], examples)],
            head(["a"], [("x-mock-response-name", "n"), ("x-mock-response-code", "500")]), allowsCORS: false)

        #expect(body(reply) == "2")
    }

    @Test func `both headers that disagree: the name still decides and the code is dropped`() {
        let examples = [example("n", 200, body: "1"), example("m", 500, body: "2")]
        let reply = MockMatch.answer(
            [route("GET", [.literal("a")], examples)],
            head(["a"], [("x-mock-response-name", "n"), ("x-mock-response-code", "500")]), allowsCORS: false)

        #expect(body(reply) == "1")
    }

    @Test func `an unknown name is a 404 naming it, even when the code would match`() {
        let reply = MockMatch.answer(
            [route("GET", [.literal("a")], named)],
            head(["a"], [("x-mock-response-name", "nope"), ("x-mock-response-code", "200")]), allowsCORS: false)

        #expect(reply.status == 404)
        #expect(body(reply) == #"{"error":"No Example named \"nope\" for GET /a"}"#)
    }

    @Test(arguments: ["418", "abc", ""])
    func `a code that matches nothing is a 404 naming it`(code: String) {
        let reply = MockMatch.answer(
            [route("GET", [.literal("a")], named)], head(["a"], [("x-mock-response-code", code)]), allowsCORS: false)

        #expect(reply.status == 404)
        #expect(body(reply) == "{\"error\":\"No Example with status \\\"\(code)\\\" for GET /a\"}")
    }

    // MARK: the reply

    @Test func `the reply is the Example's status, enabled headers in order, literal body and delay`() {
        let ex = example(
            "ok", 201,
            headers: [
                Row(name: "X-A", value: "1"), Row(name: "X-Off", value: "no", isEnabled: false), Row(name: "X-B", value: "{{b}}"),
            ],
            body: "{{name}} stays", delay: 250)

        let reply = MockMatch.answer([route("GET", [.literal("a")], [ex])], head(["a"]), allowsCORS: false)

        #expect(reply == MockReply(
            status: 201, headers: [.init(name: "X-A", value: "1"), .init(name: "X-B", value: "{{b}}")],
            body: Data("{{name}} stays".utf8), delay: .milliseconds(250)))
    }

    @Test func `a bytes Example is sent as its bytes`() {
        let bytes = Data([0xFF, 0x00, 0x81])
        let ex = Example(id: ExampleID(UUID()), name: "bin", status: 200, body: .bytes(bytes))

        let reply = MockMatch.answer([route("GET", [.literal("a")], [ex])], head(["a"]), allowsCORS: false)

        #expect(reply.body == bytes)
    }

    @Test func `CORS on adds Allow-Origin, CORS off adds nothing`() {
        let routes = [route("GET", [.literal("a")], [example("ok", headers: [Row(name: "X-A", value: "1")])])]

        let on = MockMatch.answer(routes, head(["a"]), allowsCORS: true)
        let off = MockMatch.answer(routes, head(["a"]), allowsCORS: false)

        #expect(on.headers == [.init(name: "X-A", value: "1"), .init(name: "Access-Control-Allow-Origin", value: "*")])
        #expect(off.headers == [.init(name: "X-A", value: "1")])
    }

    @Test func `an Example's own Allow-Origin is kept, in any case, and not doubled`() {
        let ex = example("ok", headers: [Row(name: "access-control-allow-origin", value: "https://a.test")])

        let reply = MockMatch.answer([route("GET", [.literal("a")], [ex])], head(["a"]), allowsCORS: true)

        #expect(reply.headers == [.init(name: "access-control-allow-origin", value: "https://a.test")])
    }

    @Test func `a disabled Allow-Origin row does not count as the Example's own`() {
        let ex = example("ok", headers: [Row(name: "Access-Control-Allow-Origin", value: "https://a.test", isEnabled: false)])

        let reply = MockMatch.answer([route("GET", [.literal("a")], [ex])], head(["a"]), allowsCORS: true)

        #expect(reply.headers == [.init(name: "Access-Control-Allow-Origin", value: "*")])
    }

    // MARK: no match

    @Test func `no route is a JSON 404 with no delay`() {
        let reply = MockMatch.answer([], head("GET", ["users", "42"]), allowsCORS: false)

        #expect(reply == MockReply(
            status: 404, headers: [.init(name: "Content-Type", value: "application/json")],
            body: Data(#"{"error":"No Example matches GET /users/42"}"#.utf8), delay: .zero))
    }

    @Test func `the 404 names the root as a slash and carries Allow-Origin when CORS is on`() {
        let reply = MockMatch.answer([], head("GET", []), allowsCORS: true)

        #expect(body(reply) == #"{"error":"No Example matches GET /"}"#)
        #expect(value(reply, "Access-Control-Allow-Origin") == "*")
    }

    @Test func `what the 404 embeds is JSON-escaped`() throws {
        let reply = MockMatch.answer([], head("GET", ["a\"b", "c\\d\n"]), allowsCORS: false)

        let decoded = try JSONDecoder().decode([String: String].self, from: reply.body)
        #expect(decoded["error"] == "No Example matches GET /a\"b/c\\d\n")
    }

    // MARK: preflight

    private let preflight: [(String, String)] = [
        ("Origin", "https://app.test"), ("access-control-request-method", "PUT"),
    ]

    @Test func `a preflight with CORS on is a 204 with the CORS headers, routes or not`() {
        let reply = MockMatch.answer([], head("OPTIONS", ["users"], preflight), allowsCORS: true)

        #expect(reply == MockReply(
            status: 204,
            headers: [
                .init(name: "Access-Control-Allow-Origin", value: "*"),
                .init(name: "Access-Control-Allow-Methods", value: "PUT"),
                .init(name: "Access-Control-Max-Age", value: "600"),
            ],
            body: Data(), delay: .zero))
    }

    @Test func `a preflight echoes the requested headers when the request sent them`() {
        let sent = preflight + [("Access-Control-Request-Headers", "content-type, x-a")]

        let reply = MockMatch.answer([], head("OPTIONS", ["users"], sent), allowsCORS: true)

        #expect(reply.headers.map(\.name) == [
            "Access-Control-Allow-Origin", "Access-Control-Allow-Methods", "Access-Control-Allow-Headers",
            "Access-Control-Max-Age",
        ])
        #expect(value(reply, "Access-Control-Allow-Headers") == "content-type, x-a")
    }

    @Test func `a preflight with CORS off is matched like any request`() {
        let options = route("OPTIONS", [.literal("users")], [example("opts", 200, body: "mine")])

        let matched = MockMatch.answer([options], head("OPTIONS", ["users"], preflight), allowsCORS: false)
        let missing = MockMatch.answer([], head("OPTIONS", ["users"], preflight), allowsCORS: false)

        #expect(body(matched) == "mine")
        #expect(missing.status == 404)
    }

    @Test func `an OPTIONS without Access-Control-Request-Method is not a preflight`() {
        let reply = MockMatch.answer([], head("OPTIONS", ["users"], [("Origin", "https://app.test")]), allowsCORS: true)

        #expect(reply.status == 404)
    }

    @Test func `a GET with Access-Control-Request-Method is not a preflight`() {
        let reply = MockMatch.answer([], head("GET", ["users"], preflight), allowsCORS: true)

        #expect(reply.status == 404)
    }
}
