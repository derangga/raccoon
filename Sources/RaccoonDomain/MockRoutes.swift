import Foundation

/// A Collection's Requests as routes (mock-server.md §Matching).
public enum MockRoutes {
    /// `requests` in sidebar order; so are the routes. A Request with no Examples has no route.
    public static func build(_ requests: [Request]) -> [MockRoute] {
        requests.filter { !$0.examples.isEmpty }.map {
            MockRoute(
                method: $0.definition.method, segments: segments(of: $0.definition.url).map(segment),
                requestName: $0.name, examples: $0.examples)
        }
    }

    /// The URL text before `?`, without its scheme and authority (or a leading `{{name}}` standing
    /// for them), split on `/`; a trailing `/` adds no segment.
    private static func segments(of url: String) -> [String] {
        var rest = Substring(url.prefix { $0 != "?" })
        let slash = rest.firstIndex(of: "/") ?? rest.endIndex
        if let scheme = rest.range(of: "://"), scheme.lowerBound <= slash {
            rest = rest[scheme.upperBound...]
            rest = rest[(rest.firstIndex(of: "/") ?? rest.endIndex)...]
        } else if rest.hasPrefix("{{") {
            rest = rest[slash...]
        }
        if rest.first == "/" { rest.removeFirst() }
        var parts = rest.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        while parts.last?.isEmpty == true { parts.removeLast() }
        return parts
    }

    private static func segment(_ text: String) -> MockSegment {
        let inner = text.hasPrefix("{{") && text.hasSuffix("}}") ? text.dropFirst(2).dropLast(2) : nil
        let isName = text.count > 1 && text.hasPrefix(":")
        let isVariable = inner.map { !$0.isEmpty && !$0.contains(where: { "{}".contains($0) }) } ?? false
        // The request path arrives percent-decoded, so the route text is decoded to meet it.
        return isName || isVariable ? .wildcard : .literal(text.removingPercentEncoding ?? text)
    }
}
