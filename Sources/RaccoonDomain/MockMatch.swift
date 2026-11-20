import Foundation

/// What the Mock Server answers a request with (mock-server.md §Answer a request). Total: every
/// head gets a reply, a 404 when nothing matches.
public enum MockMatch {
    public static func answer(_ routes: [MockRoute], _ head: MockRequestHead, allowsCORS: Bool) -> MockReply {
        if allowsCORS, let reply = preflight(head) { return reply }
        guard let route = mostSpecific(candidates(routes, head)) else {
            return notFound(head, reason: "No Example matches \(label(head))", allowsCORS: allowsCORS)
        }
        switch pick(route, head) {
        case .example(let example): return reply(example, allowsCORS: allowsCORS)
        case .none(let reason): return notFound(head, reason: "\(reason) for \(label(head))", allowsCORS: allowsCORS)
        }
    }

    private static let origin = "Access-Control-Allow-Origin"

    private static func header(_ head: MockRequestHead, _ name: String) -> String? {
        head.headers.first { $0.name.lowercased() == name }?.value
    }

    private static func label(_ head: MockRequestHead) -> String {
        "\(head.method) /\(head.path.joined(separator: "/"))"
    }

    private static func preflight(_ head: MockRequestHead) -> MockReply? {
        guard head.method == "OPTIONS", let method = header(head, "access-control-request-method") else { return nil }
        var headers: [Response.Header] = [.init(name: origin, value: "*"), .init(name: "Access-Control-Allow-Methods", value: method)]
        if let requested = header(head, "access-control-request-headers") {
            headers.append(.init(name: "Access-Control-Allow-Headers", value: requested))
        }
        headers.append(.init(name: "Access-Control-Max-Age", value: "600"))
        return MockReply(status: 204, headers: headers, body: Data(), delay: .zero)
    }

    private static func candidates(_ routes: [MockRoute], _ head: MockRequestHead) -> [MockRoute] {
        routes.filter { route in
            route.method == head.method && route.segments.count == head.path.count
                && zip(route.segments, head.path).allSatisfy { segment, text in
                    switch segment {
                    case .literal(let literal): literal == text
                    case .wildcard: !text.isEmpty
                    }
                }
        }
    }

    /// Compared segment by segment from the left, a literal beats a wildcard at the first place
    /// they differ; a tie keeps the earlier route.
    private static func mostSpecific(_ candidates: [MockRoute]) -> MockRoute? {
        func beats(_ a: MockRoute, _ b: MockRoute) -> Bool {
            for (x, y) in zip(a.segments, b.segments) where x != y { return y == .wildcard }
            return false
        }
        return candidates.reduce(nil) { best, route in
            guard let best else { return route }
            return beats(route, best) ? route : best
        }
    }

    private enum Pick {
        case example(Example)
        /// The header value that matched no Example, as the 404 words it.
        case none(String)
    }

    /// `x-mock-response-name` (the first Example of that name, preferring one with the
    /// `x-mock-response-code` status), else `x-mock-response-code`, else the first Example. A
    /// header whose value matches nothing is `.none`. With both headers the name decides: a code
    /// that matches none of the named Examples is dropped, not a 404.
    private static func pick(_ route: MockRoute, _ head: MockRequestHead) -> Pick {
        let code = header(head, "x-mock-response-code").map { $0.trimmingCharacters(in: .whitespaces) }
        let status = code.flatMap { Int($0) }
        if let name = header(head, "x-mock-response-name") {
            let named = route.examples.filter { $0.name == name }
            guard let first = named.first else { return .none("No Example named \"\(name)\"") }
            return .example(named.first { $0.status == status } ?? first)
        }
        if let code {
            guard let match = route.examples.first(where: { $0.status == status }) else {
                return .none("No Example with status \"\(code)\"")
            }
            return .example(match)
        }
        // A route from `MockRoutes.build` always has one; the init is public, so a hand-made one must not trap.
        guard let first = route.examples.first else { return .none("No Example") }
        return .example(first)
    }

    private static func reply(_ example: Example, allowsCORS: Bool) -> MockReply {
        let response = example.asResponse
        var headers = response.headers
        if allowsCORS { addOrigin(&headers) }
        return MockReply(status: response.status, headers: headers, body: response.body, delay: .milliseconds(example.delayMilliseconds))
    }

    private static func addOrigin(_ headers: inout [Response.Header]) {
        if !headers.contains(where: { $0.name.lowercased() == origin.lowercased() }) {
            headers.append(.init(name: origin, value: "*"))
        }
    }

    private static func notFound(_ head: MockRequestHead, reason: String, allowsCORS: Bool) -> MockReply {
        var headers: [Response.Header] = [.init(name: "Content-Type", value: "application/json")]
        if allowsCORS { addOrigin(&headers) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        // a [String: String] always encodes
        let body = (try? encoder.encode(["error": reason])) ?? Data()
        return MockReply(status: 404, headers: headers, body: body, delay: .zero)
    }
}
