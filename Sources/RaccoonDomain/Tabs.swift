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
