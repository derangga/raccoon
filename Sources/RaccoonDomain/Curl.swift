public struct CurlImport: Equatable, Sendable {
    public var definition: RequestDefinition
    /// Flags Raccoon did not use, for the "Ignored" note.
    public var ignoredFlags: [String]
    /// `@path`s that still have to be read.
    public var fileReferences: [String]

    public init(definition: RequestDefinition, ignoredFlags: [String], fileReferences: [String]) {
        self.definition = definition
        self.ignoredFlags = ignoredFlags
        self.fileReferences = fileReferences
    }
}

public enum PasteTarget: Equatable, Sendable {
    case currentTab
    case newDraftTab
}
