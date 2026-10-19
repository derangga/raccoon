import Foundation

/// The sidebar while its filter has a query: a view over the tree, not a second index.
public struct FilteredTree: Equatable, Sendable {
    /// Where a node's own name matched, for the highlight.
    public struct Match: Equatable, Sendable {
        public let name: String
        public let range: Range<String.Index>
    }

    public var collections: [Collection]
    /// By node path: a Collection's name, a Folder's path, a Request's or unreadable file's path.
    public var matches: [String: Match]
    /// Collections and Folders holding a match, shown open.
    public var expanded: Set<String>

    public var matchCount: Int { matches.count }
    public var matchedText: [String: String] { matches.mapValues { String($0.name[$0.range]) } }
}

/// Names only (design-system §9 Q13): never the method or the URL.
public enum TreeFilter {
    public static func matches(_ collections: [Collection], _ query: String) -> FilteredTree {
        var result = FilteredTree(collections: [], matches: [:], expanded: [])

        func match(_ name: String, at path: String) -> Bool {
            guard let range = name.localizedStandardRange(of: query) else { return false }
            result.matches[path] = FilteredTree.Match(name: name, range: range)
            return true
        }

        /// The nodes kept under `parent`, and whether any of them, or anything below, matched.
        /// Everything is kept when an ancestor matched.
        func kept(_ nodes: [TreeNode], in parent: String, ancestorMatched: Bool) -> (nodes: [TreeNode], hasMatch: Bool) {
            var hasMatch = false
            let nodes = nodes.compactMap { node -> TreeNode? in
                switch node {
                case .folder(let name, let children):
                    let path = parent + "/" + name
                    let matched = match(name, at: path)
                    let inner = kept(children, in: path, ancestorMatched: ancestorMatched || matched)
                    if inner.hasMatch { result.expanded.insert(path) }
                    hasMatch = hasMatch || matched || inner.hasMatch
                    return ancestorMatched || matched || inner.hasMatch ? .folder(name: name, children: inner.nodes) : nil
                case .request(_, _, let path), .unreadable(let path, _):
                    let matched = match(node.name, at: path)
                    hasMatch = hasMatch || matched
                    return ancestorMatched || matched ? node : nil
                }
            }
            return (nodes, hasMatch)
        }

        for collection in collections {
            let matched = match(collection.name, at: collection.name)
            let inner = kept(collection.nodes, in: collection.name, ancestorMatched: matched)
            if inner.hasMatch { result.expanded.insert(collection.name) }
            if matched || inner.hasMatch { result.collections.append(Collection(name: collection.name, nodes: inner.nodes)) }
        }
        return result
    }
}
