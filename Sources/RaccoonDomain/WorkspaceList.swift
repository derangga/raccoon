import Foundation

/// One row of the Workspace pop-up.
public struct WorkspaceTitle: Equatable, Sendable {
    public let path: String
    public let title: String
}

public enum WorkspaceList {
    /// Each Workspace by its folder name; names shared by two or more get " — <parent folder>",
    /// the others stay bare. Sorted as the sidebar sorts.
    public static func titles(_ paths: [String]) -> [WorkspaceTitle] {
        let counts = Dictionary(paths.map { (URL(filePath: $0).lastPathComponent, 1) }, uniquingKeysWith: +)
        return paths.map { path in
            let url = URL(filePath: path)
            let name = url.lastPathComponent
            let title = counts[name, default: 0] > 1 ? "\(name) — \(url.deletingLastPathComponent().lastPathComponent)" : name
            return WorkspaceTitle(path: path, title: title)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}
