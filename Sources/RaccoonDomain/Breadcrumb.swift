/// A sidebar path is a Collection's name, a Folder's path or a file's path, relative to the Data
/// Folder, joined by "/" (SidebarItem.path).
public enum SidebarPath {
    /// The Collection and Folders above a path, outermost first: "A/B/C/F.json" is ["A", "A/B", "A/B/C"].
    public static func ancestors(of path: String) -> [String] {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.indices.dropFirst().map { parts[..<$0].joined(separator: "/") }
    }
}

/// One name in the Breadcrumb. `target` is the sidebar path a click selects; nil is not clickable.
public struct BreadcrumbSegment: Equatable, Sendable {
    public let title: String
    public let target: String?

    public init(title: String, target: String?) {
        self.title = title
        self.target = target
    }
}

/// Which middle segments the "…" stands for. The first and the last are never in the range.
public enum BreadcrumbFit: Equatable, Sendable {
    case all
    case collapsed(hidden: Range<Int>)
}

/// Where the Tab's Request lives, derived from the index by RequestID, never stored on the Tab.
public struct Breadcrumb: Equatable, Sendable {
    public let segments: [BreadcrumbSegment]

    public init(segments: [BreadcrumbSegment]) {
        self.segments = segments
    }

    /// A Draft is its Tab title alone. A Request in the index is its Collection, each Folder, then
    /// the name inside its file. With no entry (its file is unreadable, or a rescan has not
    /// landed) the last known segments stay, else the Tab's title alone.
    public static func of(source: Tab.Source, title: String, index: DataFolderIndex, lastKnown: Breadcrumb?) -> Breadcrumb {
        guard case .request(let id) = source else { return Breadcrumb(segments: [BreadcrumbSegment(title: title, target: nil)]) }
        guard let path = index.path(of: id), let name = index.name(of: id) else {
            return lastKnown ?? Breadcrumb(segments: [BreadcrumbSegment(title: title, target: nil)])
        }
        let folders = SidebarPath.ancestors(of: path).map { BreadcrumbSegment(title: String($0.split(separator: "/").last ?? ""), target: $0) }
        return Breadcrumb(segments: folders + [BreadcrumbSegment(title: name, target: path)])
    }

    /// Hides middle segments, nearest the first, until first, "…" and last (and what is left of the
    /// middle) fit `available`. With two segments or fewer it is `.all`: truncation is the view's.
    /// The "…" and its separator are counted only when something is hidden. Still too narrow when
    /// every middle segment is hidden: still `.collapsed` over all of them.
    public static func fit(widths: [Double], separator: Double, ellipsis: Double, available: Double) -> BreadcrumbFit {
        let count = widths.count
        guard count > 2 else { return .all }
        if widths.reduce(0, +) + separator * Double(count - 1) <= available { return .all }
        for end in 2..<count {
            let shown = widths[..<1] + widths[end...]
            // shown segments, the "…", and a separator between each neighbour
            let width = shown.reduce(0, +) + ellipsis + separator * Double(shown.count)
            if width <= available { return .collapsed(hidden: 1..<end) }
        }
        return .collapsed(hidden: 1..<(count - 1))
    }
}
