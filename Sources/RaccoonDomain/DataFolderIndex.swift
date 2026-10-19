/// The sidebar tree plus where each Request's file is. One Request per RequestID: copying a
/// file in Finder copies its id, so the second by path order becomes an unreadable row.
public struct DataFolderIndex: Equatable, Sendable {
    public private(set) var collections: [Collection]
    private var paths: [RequestID: String] = [:]

    public init(_ collections: [Collection]) {
        var requests: [(id: RequestID, path: String)] = []
        func gather(_ nodes: [TreeNode]) {
            for node in nodes {
                switch node {
                case .folder(_, let children): gather(children)
                case .request(let id, _, _, let path): requests.append((id, path))
                case .unreadable: break
                }
            }
        }
        collections.forEach { gather($0.nodes) }

        var paths: [RequestID: String] = [:]
        var duplicates: [String: String] = [:]
        for request in requests.sorted(by: { $0.path < $1.path }) {
            if let first = paths[request.id] { duplicates[request.path] = first } else { paths[request.id] = request.path }
        }
        func marked(_ nodes: [TreeNode]) -> [TreeNode] {
            nodes.map { node in
                switch node {
                case .folder(let name, let children): .folder(name: name, children: marked(children))
                case .request(_, _, _, let path):
                    duplicates[path].map { .unreadable(path: path, reason: "Same id as \(TreeDecoder.lastComponent($0)).") } ?? node
                case .unreadable: node
                }
            }
        }
        self.collections = collections.map { Collection(name: $0.name, nodes: marked($0.nodes)) }
        self.paths = paths
    }

    public func path(of id: RequestID) -> String? {
        paths[id]
    }

    /// A Request just written into a Collection or Folder the tree already has.
    public mutating func insert(_ id: RequestID, name: String, method: String, path: String) {
        precondition(paths[id] == nil, "one file per RequestID")
        let folders = path.split(separator: "/").dropLast().map(String.init)
        guard let c = collections.firstIndex(where: { $0.name == folders.first }) else {
            preconditionFailure("insert into a Collection the index does not have: \(path)")
        }
        collections[c].nodes = Self.inserting(.request(id, name: name, method: method, path: path), into: collections[c].nodes, at: folders.dropFirst())
        paths[id] = path
    }

    private static func inserting(_ request: TreeNode, into nodes: [TreeNode], at folders: ArraySlice<String>) -> [TreeNode] {
        guard let folder = folders.first else {
            let isFolder = { (node: TreeNode) in if case .folder = node { true } else { false } }
            return nodes.filter(isFolder) + (nodes.filter { !isFolder($0) } + [request]).sortedByName()
        }
        guard let f = nodes.firstIndex(where: { if case .folder(folder, _) = $0 { true } else { false } }),
              case .folder(_, let children) = nodes[f]
        else { preconditionFailure("insert into a Folder the index does not have: \(folder)") }
        var nodes = nodes
        nodes[f] = .folder(name: folder, children: inserting(request, into: children, at: folders.dropFirst()))
        return nodes
    }
}
