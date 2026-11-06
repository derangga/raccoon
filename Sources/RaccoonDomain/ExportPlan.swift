import Foundation

/// A Request file left out of the export: the scan marked it `.unreadable`, or it no longer decodes.
/// `reason` is the text the unreadable row shows.
public struct ExportSkip: Equatable, Sendable {
    public var path: String
    public var reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

/// What the Collection Export sheet shows, and the bytes Export… writes: computed once, so the
/// warning and the counts describe the file. Not Codable.
public struct ExportPlan: Equatable, Sendable {
    public var collection: ExportCollection
    public var requests: Int
    public var folders: Int
    public var findings: [CredentialFinding]
    public var skipped: [ExportSkip]
    /// Names of Requests that are Dirty in a Tab: the file holds what is saved.
    public var dirtyRequests: [String]
    public var data: Data

    public init(
        collection: ExportCollection, requests: Int, folders: Int, findings: [CredentialFinding],
        skipped: [ExportSkip], dirtyRequests: [String], data: Data
    ) {
        self.collection = collection
        self.requests = requests
        self.folders = folders
        self.findings = findings
        self.skipped = skipped
        self.dirtyRequests = dirtyRequests
        self.data = data
    }
}

/// One finished step, in this order. The last carries the plan.
public enum ExportStep: Equatable, Sendable {
    case read(count: Int)
    case formatted
    case scanned(ExportPlan)
}

extension ExportCollection {
    /// Every Request, in tree order.
    public var requests: [Request] {
        func gather(_ nodes: [ExportNode]) -> [Request] {
            nodes.flatMap { node -> [Request] in
                switch node {
                case .folder(_, let children): gather(children)
                case .request(let request): [request]
                }
            }
        }
        return gather(nodes)
    }

    /// Every Folder, at any depth.
    public var folderCount: Int {
        func count(_ nodes: [ExportNode]) -> Int {
            nodes.reduce(0) { total, node in
                if case .folder(_, let children) = node { total + 1 + count(children) } else { total }
            }
        }
        return count(nodes)
    }
}

/// Postman Export's reading half, the pure part.
public enum CollectionExport {
    /// The sidebar's order, chosen here because the exporter keeps the order it is given: Folders
    /// first, then Requests and unreadable rows together, each by the name shown, at every depth.
    public static func sorted(_ nodes: [TreeNode]) -> [TreeNode] {
        let byName = { (a: TreeNode, b: TreeNode) in a.name.localizedStandardCompare(b.name) == .orderedAscending }
        var folders: [TreeNode] = []
        var rest: [TreeNode] = []
        for node in nodes {
            if case .folder(let name, let children) = node {
                folders.append(.folder(name: name, children: sorted(children)))
            } else {
                rest.append(node)
            }
        }
        return folders.sorted(by: byName) + rest.sorted(by: byName)
    }
}
