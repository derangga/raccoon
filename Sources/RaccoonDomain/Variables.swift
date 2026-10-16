public struct VariableEntry: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case plain(String)
        /// The value lives in the Keychain. Holding none here keeps it out of every encoded file.
        case secret
    }

    public var name: VariableName
    public var isEnabled: Bool
    public var value: Value

    public init(name: VariableName, isEnabled: Bool = true, value: Value) {
        self.name = name
        self.isEnabled = isEnabled
        self.value = value
    }
}

public struct Environment: Equatable, Sendable {
    public var name: String
    public var entries: [VariableEntry]

    public init(name: String, entries: [VariableEntry]) {
        self.name = name
        self.entries = entries
    }
}

public struct Globals: Equatable, Sendable {
    public var entries: [VariableEntry]

    public init(entries: [VariableEntry]) {
        self.entries = entries
    }
}

/// The Active Environment's entries over Globals, flattened once per send or highlight pass.
public struct VariableScope: Equatable, Sendable {
    public var values: [VariableName: String]

    public init(values: [VariableName: String]) {
        self.values = values
    }
}
