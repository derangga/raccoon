public indirect enum TreeNode: Equatable, Sendable {
    case folder(name: String, children: [TreeNode])
    case request(RequestID, name: String, path: String)
    /// A file that did not decode. It is kept byte for byte and never rewritten.
    case unreadable(path: String, reason: String)
}

public struct Collection: Equatable, Sendable {
    public var name: String
    public var nodes: [TreeNode]

    public init(name: String, nodes: [TreeNode]) {
        self.name = name
        self.nodes = nodes
    }
}
