import Foundation

/// The sidebar while its filter has a query: a view over the tree, not a second index.
public struct FilteredTree: Equatable, Sendable {
    /// Where a node's own name matched, for the highlight: one run for a substring, one per
    /// stretch of adjacent letters for a gap match.
    public struct Match: Equatable, Sendable {
        public let name: String
        public let ranges: [Range<String.Index>]
    }

    public var collections: [Collection]
    /// By node path: a Collection's name, a Folder's path, a Request's or unreadable file's path.
    public var matches: [String: Match]
    /// Collections and Folders holding a match, shown open.
    public var expanded: Set<String>

    public var matchCount: Int { matches.count }
    public var matchedText: [String: [String]] { matches.mapValues { match in match.ranges.map { String(match.name[$0]) } } }
}

/// Names only (design-system §9 Q13): never the method or the URL. A substring first, else
/// the query's letters in order with gaps (Q19).
public enum TreeFilter {
    private enum Hit { case substring, subsequence }

    public static func matches(_ collections: [Collection], _ query: String) -> FilteredTree {
        var result = FilteredTree(collections: [], matches: [:], expanded: [])
        let wanted = query.map(fold)
        let scalars = Array(query.folding(options: folding, locale: nil).unicodeScalars)

        func match(_ name: String, at path: String) -> Hit? {
            let hit: Hit
            let ranges: [Range<String.Index>]
            if let range = name.localizedStandardRange(of: query) {
                (hit, ranges) = (.substring, [range])
            } else if let runs = subsequence(wanted, scalars, in: name) {
                (hit, ranges) = (.subsequence, runs)
            } else {
                return nil
            }
            result.matches[path] = FilteredTree.Match(name: name, ranges: ranges)
            return hit
        }

        /// The nodes kept under `parent`, and whether any of them, or anything below, matched.
        /// Everything is kept when an ancestor matched as a substring: a gap match on a long
        /// container name is usually an accident.
        func kept(_ nodes: [TreeNode], in parent: String, ancestorMatched: Bool) -> (nodes: [TreeNode], hasMatch: Bool) {
            var hasMatch = false
            let nodes = nodes.compactMap { node -> TreeNode? in
                switch node {
                case .folder(let name, let children):
                    let path = parent + "/" + name
                    let hit = match(name, at: path)
                    let matched = hit != nil
                    let inner = kept(children, in: path, ancestorMatched: ancestorMatched || hit == .substring)
                    if inner.hasMatch { result.expanded.insert(path) }
                    hasMatch = hasMatch || matched || inner.hasMatch
                    return ancestorMatched || matched || inner.hasMatch ? .folder(name: name, children: inner.nodes) : nil
                case .request(_, _, _, let path), .unreadable(let path, _):
                    let matched = match(node.name, at: path) != nil
                    hasMatch = hasMatch || matched
                    return ancestorMatched || matched ? node : nil
                }
            }
            return (nodes, hasMatch)
        }

        for collection in collections {
            let hit = match(collection.name, at: collection.name)
            let inner = kept(collection.nodes, in: collection.name, ancestorMatched: hit == .substring)
            if inner.hasMatch { result.expanded.insert(collection.name) }
            if hit != nil || inner.hasMatch { result.collections.append(Collection(name: collection.name, nodes: inner.nodes)) }
        }
        return result
    }

    private static let folding: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    private static func fold(_ character: Character) -> String {
        String(character).folding(options: folding, locale: nil)
    }

    /// The first stretch of `name` that holds `wanted` in order, shrunk from its end (fzf v1),
    /// so "refnd" in "Purge refund cache" lands on "refund", not the r and e of "Purge".
    /// Adjacent letters merge into one run.
    /// `scalars` is the folded query, for a cheap first pass that rejects most names before
    /// any per-Character work (environment-facts.md, Sidebar filter speed).
    private static func subsequence(_ wanted: [String], _ scalars: [Unicode.Scalar], in name: String) -> [Range<String.Index>]? {
        guard !wanted.isEmpty else { return nil }
        let folded = name.folding(options: folding, locale: nil)
        var rest = scalars[...]
        for scalar in folded.unicodeScalars where scalar == rest.first {
            rest.removeFirst()
            if rest.isEmpty { break }
        }
        guard rest.isEmpty else { return nil }

        let indices = Array(name.indices)
        // Per Character only when folding changed the count.
        let letters = folded.count == indices.count ? folded.map(String.init) : name.map(fold)
        var next = 0
        guard let end = letters.indices.first(where: { i in
            if letters[i] == wanted[next] { next += 1 }
            return next == wanted.count
        }) else { return nil }

        var hits: [Int] = []
        for i in stride(from: end, through: 0, by: -1) where letters[i] == wanted[wanted.count - 1 - hits.count] {
            hits.append(i)
            if hits.count == wanted.count { break }
        }
        var runs: [Range<String.Index>] = []
        for i in hits.reversed() {
            let range = indices[i]..<name.index(after: indices[i])
            if let last = runs.last, last.upperBound == range.lowerBound {
                runs[runs.count - 1] = last.lowerBound..<range.upperBound
            } else {
                runs.append(range)
            }
        }
        return runs
    }
}
