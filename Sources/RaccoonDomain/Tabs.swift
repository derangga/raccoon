public struct Tab: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case draft
        case request(RequestID)
    }

    public let id: TabID
    public var source: Source
    /// The working copy.
    public var definition: RequestDefinition
    /// What is on disk; nil for a Draft.
    public var baseline: RequestDefinition?
    /// Never written to the Session.
    public var response: ResponseState
    public var isChangedOnDisk: Bool

    public init(
        id: TabID, source: Source, definition: RequestDefinition, baseline: RequestDefinition?,
        response: ResponseState = .idle, isChangedOnDisk: Bool = false
    ) {
        self.id = id
        self.source = source
        self.definition = definition
        self.baseline = baseline
        self.response = response
        self.isChangedOnDisk = isChangedOnDisk
    }

    /// Edits not written back. A Draft has no baseline, so it is never Dirty.
    public var isDirty: Bool {
        if case .request = source { definition != baseline } else { false }
    }

    /// What closing would lose, so what the close prompt asks about.
    public var hasLosableContent: Bool {
        isDirty || (source == .draft && definition != .empty)
    }

    /// The tab strip's name for a Draft: "Draft" without a URL, else its path, else the URL as
    /// typed. A Request Tab shows its Request's name from the index instead (tabs.md).
    public var title: String {
        Self.title(url: definition.url) ?? "Draft"
    }

    /// What names a request that has no name: its URL's path, else the URL as typed; nil
    /// without a URL.
    public static func title(url: String) -> String? {
        let url = url.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return nil }
        let afterScheme = url.range(of: "://").map { url[$0.upperBound...] } ?? url[...]
        guard let slash = afterScheme.firstIndex(of: "/") else { return url }
        let path = afterScheme[slash...]
        return String(path.prefix { $0 != "?" && $0 != "#" })
    }

    public var snapshot: TabSnapshot {
        TabSnapshot(id: id, source: source, definition: definition, baseline: baseline)
    }
}

/// A Tab minus its Response.
public struct TabSnapshot: Equatable, Sendable {
    public let id: TabID
    public var source: Tab.Source
    public var definition: RequestDefinition
    public var baseline: RequestDefinition?

    public init(id: TabID, source: Tab.Source, definition: RequestDefinition, baseline: RequestDefinition?) {
        self.id = id
        self.source = source
        self.definition = definition
        self.baseline = baseline
    }
}

public struct Session: Equatable, Sendable {
    public var tabs: [TabSnapshot]
    public var selected: TabID?
    /// An Environment's name; none when its file is gone.
    public var activeEnvironment: String?

    public init(tabs: [TabSnapshot], selected: TabID?, activeEnvironment: String?) {
        self.tabs = tabs
        self.selected = selected
        self.activeEnvironment = activeEnvironment
    }
}

/// What ⌘W does with a Tab (tabs.md §close): ask first, or close at once. Always discarding
/// skips the sheet even for losable content.
public enum CloseStep: Equatable, Sendable {
    case close, ask

    public init(hasLosableContent: Bool, alwaysDiscards: Bool) {
        self = hasLosableContent && !alwaysDiscards ? .ask : .close
    }
}
