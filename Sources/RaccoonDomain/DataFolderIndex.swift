/// The sidebar tree plus where each Request's file is. One Request per RequestID: copying a
/// file in Finder copies its id, so the second by path order becomes an unreadable row.
public struct DataFolderIndex: Equatable, Sendable {
    public private(set) var collections: [Collection]
    private struct Entry: Equatable, Sendable {
        var path: String
        var name: String
    }

    private var entries: [RequestID: Entry] = [:]

    public init(_ collections: [Collection]) {
        var requests: [(id: RequestID, name: String, path: String)] = []
        func gather(_ nodes: [TreeNode]) {
            for node in nodes {
                switch node {
                case .folder(_, let children): gather(children)
                case .request(let id, let name, _, let path): requests.append((id, name, path))
                case .unreadable: break
                }
            }
        }
        collections.forEach { gather($0.nodes) }

        var entries: [RequestID: Entry] = [:]
        var duplicates: [String: String] = [:]
        for request in requests.sorted(by: { $0.path < $1.path }) {
            if let first = entries[request.id] { duplicates[request.path] = first.path } else { entries[request.id] = Entry(path: request.path, name: request.name) }
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
        self.entries = entries
    }

    public func path(of id: RequestID) -> String? {
        entries[id]?.path
    }

    /// The name inside the file: a Request Tab's name in the tab strip.
    public func name(of id: RequestID) -> String? {
        entries[id]?.name
    }

    /// Every Collection and Folder as a path, in tree order: the Save sheet's Location pop-up.
    public var folders: [String] {
        func walk(_ nodes: [TreeNode], in parent: String) -> [String] {
            nodes.flatMap { node -> [String] in
                guard case .folder(let name, let children) = node else { return [] }
                return [parent + "/" + name] + walk(children, in: parent + "/" + name)
            }
        }
        return collections.flatMap { [$0.name] + walk($0.nodes, in: $0.name) }
    }

    /// The files directly in a Collection or Folder, readable or not: names a new file must avoid.
    public func fileNames(in folder: String) -> Set<String> {
        var nodes = collections.first { $0.name == folder.split(separator: "/").first.map(String.init) }?.nodes ?? []
        for name in folder.split(separator: "/").dropFirst() {
            guard case .folder(_, let children)? = nodes.first(where: { if case .folder(String(name), _) = $0 { true } else { false } })
            else { return [] }
            nodes = children
        }
        return Set(nodes.compactMap { node in
            switch node {
            case .folder: nil
            case .request(_, _, _, let path), .unreadable(let path, _): TreeDecoder.lastComponent(path)
            }
        })
    }

    /// A Request just written into a Collection or Folder the tree already has.
    public mutating func insert(_ id: RequestID, name: String, method: String, path: String) {
        precondition(entries[id] == nil, "one file per RequestID")
        let folders = path.split(separator: "/").dropLast().map(String.init)
        guard let c = collections.firstIndex(where: { $0.name == folders.first }) else {
            preconditionFailure("insert into a Collection the index does not have: \(path)")
        }
        collections[c].nodes = Self.inserting(.request(id, name: name, method: method, path: path), into: collections[c].nodes, at: folders.dropFirst())
        entries[id] = Entry(path: path, name: name)
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
