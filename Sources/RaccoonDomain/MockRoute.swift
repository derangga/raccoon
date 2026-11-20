import Foundation

/// One piece of a route's path: its own text, or any one non-empty segment (`:name`, or a whole
/// `{{name}}`).
public enum MockSegment: Equatable, Sendable {
    case literal(String)
    case wildcard
}

/// One Request with Examples as the Mock Server sees it. It holds the Examples, not the Request's
/// id: routes are swapped in whole and answered from as values.
public struct MockRoute: Equatable, Sendable {
    public var method: String
    public var segments: [MockSegment]
    public var requestName: String
    public var examples: [Example]

    public init(method: String, segments: [MockSegment], requestName: String, examples: [Example]) {
        self.method = method
        self.segments = segments
        self.requestName = requestName
        self.examples = examples
    }
}
