/// What a Tab edits: a Request's definition, or an Example.
public enum TabContent: Equatable, Sendable {
    case request(RequestDefinition)
    case example(Example)
}

public struct Tab: Equatable, Sendable {
    public enum Source: Hashable, Sendable {
        case draft
        case request(RequestID)
        case example(RequestID, ExampleID)

        /// The Request whose file the Tab is about; nil for a Draft.
        public var requestID: RequestID? {
            switch self {
            case .draft: nil
            case .request(let id), .example(let id, _): id
            }
        }
    }

    public let id: TabID
    public var source: Source
    /// The working copy. An `.example` only with an `.example` source.
    public var content: TabContent
    /// What is on disk; nil for a Draft, and for an Example that is not on disk (its Request or it
    /// was deleted, and ⌘S writes it again).
    public var baseline: TabContent?
    /// Never written to the Session.
    public var response: ResponseState
    public var isChangedOnDisk: Bool

    public init(
        id: TabID, source: Source, content: TabContent, baseline: TabContent?,
        response: ResponseState = .idle, isChangedOnDisk: Bool = false
    ) {
        self.id = id
        self.source = source
        self.content = content
        self.baseline = baseline
        self.response = response
        self.isChangedOnDisk = isChangedOnDisk
    }

    /// A Draft's or a Request Tab's.
    public init(
        id: TabID, source: Source, definition: RequestDefinition, baseline: RequestDefinition?,
        response: ResponseState = .idle, isChangedOnDisk: Bool = false
    ) {
        self.init(id: id, source: source, content: .request(definition), baseline: baseline.map { .request($0) },
                  response: response, isChangedOnDisk: isChangedOnDisk)
    }

    /// The working copy of a Draft or Request Tab. An Example Tab has no definition: it reads
    /// `.empty` and an assignment is ignored, so the editing code for requests cannot reach it.
    public var definition: RequestDefinition {
        get { if case .request(let definition) = content { definition } else { .empty } }
        set { if case .request = content { content = .request(newValue) } }
    }

    /// The working copy of an Example Tab.
    public var example: Example? {
        if case .example(let example) = content { example } else { nil }
    }

    /// Edits not written back. A Draft has no baseline, so it is never Dirty. An Example Tab with
    /// no baseline is not on disk, so it is.
    public var isDirty: Bool {
        source != .draft && content != baseline
    }

    /// What closing would lose, so what the close prompt asks about.
    public var hasLosableContent: Bool {
        isDirty || (source == .draft && definition != .empty)
    }

    /// The tab strip's name for a Draft: "Draft" without a URL, else its path, else the URL as
    /// typed. A Request Tab shows its Request's name from the index instead (tabs.md); an
    /// Example Tab its working copy's name.
    public var title: String {
        if let example { return example.name }
        return Self.title(url: definition.url) ?? "Draft"
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
        TabSnapshot(id: id, source: source, content: content, baseline: baseline)
    }
}

/// A Tab minus its Response.
public struct TabSnapshot: Equatable, Sendable {
    public let id: TabID
    public var source: Tab.Source
    public var content: TabContent
    public var baseline: TabContent?

    public init(id: TabID, source: Tab.Source, content: TabContent, baseline: TabContent?) {
        self.id = id
        self.source = source
        self.content = content
        self.baseline = baseline
    }

    public init(id: TabID, source: Tab.Source, definition: RequestDefinition, baseline: RequestDefinition?) {
        self.init(id: id, source: source, content: .request(definition), baseline: baseline.map { .request($0) })
    }

    /// `.empty` for an Example Tab, as Tab.definition.
    public var definition: RequestDefinition {
        if case .request(let definition) = content { definition } else { .empty }
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
