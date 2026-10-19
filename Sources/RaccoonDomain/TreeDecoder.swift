import Foundation

/// The Data Folder's files as the sidebar tree. Top-level folders are Collections, except
/// `environments/`; deeper folders are Folders; each `.json` is a Request or an unreadable row.
public enum TreeDecoder {
    public static func collections(_ scan: DataFolderScan) -> [Collection] {
        let folders = Dictionary(grouping: scan.folders, by: parent)
        let files = Dictionary(grouping: scan.files.keys, by: parent)

        func nodes(in path: String) -> [TreeNode] {
            let subfolders = (folders[path] ?? []).map { TreeNode.folder(name: lastComponent($0), children: nodes(in: $0)) }
            let leaves = (files[path] ?? []).map { node(scan.files[$0]!, path: $0) }
            return subfolders.sortedByName() + leaves.sortedByName()
        }

        return (folders[""] ?? [])
            .filter { $0 != "environments" }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { Collection(name: $0, nodes: nodes(in: $0)) }
    }

    private static func node(_ data: Data, path: String) -> TreeNode {
        do {
            let request = try RequestFile.decode(data)
            return .request(request.id, name: request.name, method: request.definition.method, path: path)
        } catch {
            return .unreadable(path: path, reason: error.reason)
        }
    }

    static func parent(_ path: String) -> String {
        path.range(of: "/", options: .backwards).map { String(path[..<$0.lowerBound]) } ?? ""
    }

    static func lastComponent(_ path: String) -> String {
        String(path.split(separator: "/").last ?? "")
    }
}

extension [TreeNode] {
    /// As Finder sorts: by the name shown. Callers keep Folders before the rest.
    func sortedByName() -> [TreeNode] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
