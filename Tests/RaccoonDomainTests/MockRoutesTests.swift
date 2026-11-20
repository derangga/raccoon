import Foundation
import RaccoonDomain
import Testing

/// Turning a Collection's Requests into routes (mock-server.md §Matching).
struct MockRoutesTests {
    private func makeRequest(_ method: String, _ url: String, examples: Int = 1) -> Request {
        var definition = RequestDefinition.empty
        definition.method = method
        definition.url = url
        return Request(
            id: RequestID(UUID()), name: "\(method) \(url)", definition: definition,
            examples: (0..<examples).map { Example(id: ExampleID(UUID()), name: "e\($0)", status: 200, body: .text("")) })
    }

    private func segments(_ url: String) -> [MockSegment] {
        MockRoutes.build([makeRequest("GET", url)]).first?.segments ?? []
    }

    @Test(arguments: [
        ("https://api.example.com/users/:id", [MockSegment.literal("users"), .wildcard]),
        ("http://localhost:3000/users", [.literal("users")]),
        ("{{baseUrl}}/users/:id", [.literal("users"), .wildcard]),
        ("{{host}}/v1/{{version}}/items", [.literal("v1"), .wildcard, .literal("items")]),
        ("{{scheme}}://{{host}}/users", [.literal("users")]),
        ("https://api.example.com", []),
        ("{{baseUrl}}", []),
        ("{{baseUrl}}/", []),
        ("https://api.example.com/users/", [.literal("users")]),
        ("https://api.example.com/users?page=2&x=/a/b", [.literal("users")]),
        ("/users/me", [.literal("users"), .literal("me")]),
        ("https://h/a%20b/:", [.literal("a b"), .literal(":")]),
        ("https://h/a%2Fb", [.literal("a/b")]),
        ("https://h/{{a}}{{b}}/{{}}/x{{a}}", [.literal("{{a}}{{b}}"), .literal("{{}}"), .literal("x{{a}}")]),
        ("{{baseUrl}}/redirect/http://x", [.literal("redirect"), .literal("http:"), .literal(""), .literal("x")]),
    ])
    func `the URL text becomes path segments`(url: String, expected: [MockSegment]) {
        #expect(segments(url) == expected)
    }

    @Test func `a route holds its method, Request name and Examples`() throws {
        let get = makeRequest("GET", "{{baseUrl}}/users", examples: 2)

        let route = try #require(MockRoutes.build([get]).first)

        #expect(route == MockRoute(method: "GET", segments: [.literal("users")], requestName: get.name, examples: get.examples))
    }

    @Test func `a Request with no Examples makes no route and the others keep sidebar order`() {
        let routes = MockRoutes.build([makeRequest("GET", "/a"), makeRequest("GET", "/b", examples: 0), makeRequest("POST", "/c")])

        #expect(routes.map(\.segments) == [[.literal("a")], [.literal("c")]])
        #expect(routes.map(\.method) == ["GET", "POST"])
    }
}
