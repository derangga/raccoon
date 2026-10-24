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

    /// Enabled Globals, then the enabled Active Environment entries over them by name. A secret
    /// takes its value from `secrets`; one missing there is absent, so it is undefined, and an
    /// Environment's secret never falls back to a Global of the same name (variables.md).
    public init(active: Environment?, globals: Globals, secrets: [VariableName: String]) {
        var values: [VariableName: String] = [:]
        for entry in globals.entries + (active?.entries ?? []) where entry.isEnabled {
            switch entry.value {
            case .plain(let value): values[entry.name] = value
            case .secret: values[entry.name] = secrets[entry.name]
            }
        }
        self.values = values
    }
}

/// Which names resolve, where from, and which of those are secrets, from the same merge as
/// VariableScope: a plain value is kept, a secret has none here, so a highlight pass or a tooltip
/// never reads the Keychain (cardinality.md).
public struct VariableKinds: Equatable, Sendable {
    private struct Winner: Equatable, Sendable {
        var source: String
        var value: VariableEntry.Value
    }

    private var winners: [VariableName: Winner] = [:]
    private var environment: String?

    public init(active: Environment?, globals: Globals) {
        environment = active?.name
        for (source, entries) in [("Globals", globals.entries), (active?.name ?? "", active?.entries ?? [])] {
            for entry in entries where entry.isEnabled { winners[entry.name] = Winner(source: source, value: entry.value) }
        }
    }

    /// What the hover tooltip says about `name`.
    public func tooltip(for name: VariableName) -> VariableTooltip {
        switch winners[name] {
        case nil: .undefined(name, environment: environment)
        case let winner?:
            switch winner.value {
            case .plain(let value): .defined(name, source: winner.source, value: value)
            case .secret: .secret(name, source: winner.source)
            }
        }
    }

    /// Every `{{name}}` in `text`: variableDefined, variableSecret or variableUndefined.
    public func ranges(in text: String) -> [HighlightRange] {
        VariableTokens.ranges(text).map { token in
            let kind: ColorToken = switch winners[token.name]?.value {
            case nil: .variableUndefined
            case .secret?: .variableSecret
            case .plain?: .variableDefined
            }
            return HighlightRange(range: token.range, token: kind)
        }
    }

    /// The enabled names in scope that hold `prefix`, ignoring case: those that start with it
    /// first, then the rest, each by name.
    public func suggestions(matching prefix: String) -> [VariableSuggestion] {
        let wanted = prefix.lowercased()
        let found = winners.compactMap { name, winner -> (starts: Bool, VariableSuggestion)? in
            let lower = name.rawValue.lowercased()
            guard wanted.isEmpty || lower.contains(wanted) else { return nil }
            return (lower.hasPrefix(wanted), VariableSuggestion(name: name, source: winner.source, isSecret: winner.value == .secret))
        }
        return found.sorted { a, b in
            a.starts != b.starts ? a.starts : a.1.name.rawValue.localizedStandardCompare(b.1.name.rawValue) == .orderedAscending
        }.map(\.1)
    }

    public func holdsUndefined(_ text: String) -> Bool {
        VariableTokens.ranges(text).contains { winners[$0.name] == nil }
    }
}

/// What the hover popover shows for a `{{name}}` (design-system §6 Variable popover).
public enum VariableTooltip: Equatable, Sendable {
    case defined(VariableName, source: String, value: String)
    /// Never a value: the Keychain is not read for a tooltip.
    case secret(VariableName, source: String)
    /// `environment` is the Active Environment's name, if there is one.
    case undefined(VariableName, environment: String?)

    public var name: VariableName {
        switch self {
        case .defined(let name, _, _), .secret(let name, _), .undefined(let name, _): name
        }
    }

    /// The Environment's name, or "Globals"; none for an undefined name.
    public var source: String? {
        switch self {
        case .defined(_, let source, _), .secret(_, let source): source
        case .undefined: nil
        }
    }

    /// The second line: the value, "Secret", or where the name was looked for.
    public var detail: String {
        switch self {
        case .defined(_, _, let value): value
        case .secret: "Secret"
        case .undefined(_, let environment): "Not defined in " + (environment.map { "\($0) or Globals" } ?? "Globals")
        }
    }
}
