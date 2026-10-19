import Foundation

public indirect enum TreeNode: Equatable, Sendable {
    case folder(name: String, children: [TreeNode])
    /// `method` is for the sidebar badge.
    case request(RequestID, name: String, method: String, path: String)
    /// A file that did not decode. It is kept byte for byte and never rewritten.
    case unreadable(path: String, reason: String)
}

/// What the Data Folder holds, by path relative to its root. Folders are listed apart from
/// files so an empty Collection or Folder still shows.
public struct DataFolderScan: Equatable, Sendable {
    public var files: [String: Data]
    public var folders: Set<String>

    public init(files: [String: Data], folders: Set<String>) {
        self.files = files
        self.folders = folders
    }
}

public struct Collection: Equatable, Sendable {
    public var name: String
    public var nodes: [TreeNode]

    public init(name: String, nodes: [TreeNode]) {
        self.name = name
        self.nodes = nodes
    }
}

extension TreeNode {
    /// What the sidebar shows: an unreadable row has no Request name, so its file name.
    public var name: String {
        switch self {
        case .folder(let name, _), .request(_, let name, _, _): name
        case .unreadable(let path, _): String(path.split(separator: "/").last ?? "")
        }
    }
}

/// Raccoon's own changes, applied to the last scan in memory so the tree follows at once with
/// no disk scan (collections.md §renameOrMove).
extension DataFolderScan {
    /// `path` and everything under it.
    public func paths(under path: String) -> Set<String> {
        let inside = { (candidate: String) in candidate == path || candidate.hasPrefix(path + "/") }
        return Set(files.keys.filter(inside)).union(folders.filter(inside))
    }

    public func moving(_ path: String, to newPath: String) -> DataFolderScan {
        let moved = { (candidate: String) in
            candidate == path ? newPath : candidate.hasPrefix(path + "/") ? newPath + candidate.dropFirst(path.count) : candidate
        }
        return DataFolderScan(files: Dictionary(uniqueKeysWithValues: files.map { (moved($0.key), $0.value) }),
                              folders: Set(folders.map(moved)))
    }

    public func removing(_ path: String) -> DataFolderScan {
        let gone = paths(under: path)
        return DataFolderScan(files: files.filter { !gone.contains($0.key) }, folders: folders.subtracting(gone))
    }
}
