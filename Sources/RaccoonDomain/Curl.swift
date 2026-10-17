public struct CurlImport: Equatable, Sendable {
    public var definition: RequestDefinition
    /// Flags Raccoon did not use, for the "Ignored" note.
    public var ignoredFlags: [String]
    /// `@path`s that still have to be read.
    public var fileReferences: [String]
    /// Other curl commands in the paste, for the "2 more commands" note.
    public var skippedCommands: Int

    public init(definition: RequestDefinition, ignoredFlags: [String], fileReferences: [String], skippedCommands: Int) {
        self.definition = definition
        self.ignoredFlags = ignoredFlags
        self.fileReferences = fileReferences
        self.skippedCommands = skippedCommands
    }
}

public enum PasteTarget: Equatable, Sendable {
    case currentTab
    case newDraftTab
}

extension PasteTarget {
    /// The empty Draft is replaced; anything with something in it is kept and gets a new Tab.
    public static func `for`(_ tab: Tab) -> PasteTarget {
        tab.source == .draft && tab.definition == .empty && tab.response == .idle ? .currentTab : .newDraftTab
    }
}
