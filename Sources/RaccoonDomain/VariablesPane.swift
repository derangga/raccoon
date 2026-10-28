/// What the inspector's Variables pane lists for one Tab (variables.md §The Variables pane):
/// the names it uses that nothing defines, the Active Environment's enabled entries, then
/// Globals' enabled entries. A secret is shown as such, so the pane never reads the Keychain.
public struct VariablesPane: Equatable, Sendable {
    public enum Shown: Equatable, Sendable {
        case value(String)
        case secret
        /// An undefined name: the editor sections that use it, in editor order.
        case usedIn([String])
    }

    public struct Entry: Equatable, Sendable {
        public var name: VariableName
        public var shown: Shown
        /// A Global the Active Environment replaces: struck out.
        public var isOverridden: Bool
        /// Where the entry is in its file's entries, Disabled Rows counted, so an edit writes that
        /// row; nil for a name nothing defines.
        public var index: Int?

        public init(name: VariableName, shown: Shown, isOverridden: Bool = false, index: Int? = nil) {
            self.name = name
            self.shown = shown
            self.isOverridden = isOverridden
            self.index = index
        }
    }

    public enum Group: Equatable, Sendable { case undefined, active, globals }

    public struct Place: Equatable, Sendable {
        public var group: Group
        public var index: Int

        public init(group: Group, index: Int) {
            self.group = group
            self.index = index
        }
    }

    public var undefined: [Entry]
    /// The Active Environment's name; nil for No Environment.
    public var environment: String?
    public var active: [Entry]
    public var globals: [Entry]

    public init(definition: RequestDefinition, active: Environment?, globals: Globals) {
        let uses = Self.uses(in: definition)
        let used = Set(uses.map(\.name))
        func shown(_ value: VariableEntry.Value) -> Shown {
            switch value {
            case .plain(let text): .value(text)
            case .secret: .secret
            }
        }
        let enabled = (active?.entries ?? []).enumerated().filter(\.element.isEnabled)
        let activeNames = Set(enabled.map(\.element.name))
        let enabledGlobals = globals.entries.enumerated().filter(\.element.isEnabled)
        let defined = activeNames.union(enabledGlobals.map(\.element.name))

        undefined = uses.filter { !defined.contains($0.name) }.map { Entry(name: $0.name, shown: .usedIn($0.sections)) }
        environment = active?.name
        // Stable partition: the names this Tab uses first, each half in file order.
        self.active = (enabled.filter { used.contains($0.element.name) } + enabled.filter { !used.contains($0.element.name) })
            .map { Entry(name: $0.element.name, shown: shown($0.element.value), index: $0.offset) }
        self.globals = enabledGlobals.map {
            Entry(name: $0.element.name, shown: shown($0.element.value), isOverridden: activeNames.contains($0.element.name), index: $0.offset)
        }
    }

    /// Where `name` resolves: Not defined, the Active Environment, or a Global no Environment
    /// entry overrides. Nil when the pane does not list it.
    public func row(of name: VariableName) -> Place? {
        for (group, entries) in [(Group.undefined, undefined), (.active, active), (.globals, globals)] {
            if let index = entries.firstIndex(where: { $0.name == name && !$0.isOverridden }) { return Place(group: group, index: index) }
        }
        return nil
    }

    /// Every name the Tab sends, in first-use order, with the sections it appears in. Disabled
    /// Rows and Parts are not sent, so they do not count.
    static func uses(in definition: RequestDefinition) -> [(name: VariableName, sections: [String])] {
        func texts(_ rows: [Row]) -> [String] { rows.filter(\.isEnabled).flatMap { [$0.name, $0.value] } }
        let body: [String] = switch definition.body {
        case .none: []
        case .raw(_, let text): [text]
        case .formURLEncoded(let rows): texts(rows)
        case .multipart(let parts):
            parts.filter(\.isEnabled).flatMap { part -> [String] in
                switch part.content {
                case .text(let text): [part.name, text]
                case .file(let path): [part.name, path]
                }
            }
        }
        let auth: [String] = switch definition.auth {
        case .none: []
        case .basic(let user, let password): [user, password]
        case .bearer(let token): [token]
        }
        let sections: [(String, [String])] = [
            ("URL", [definition.url]), ("Params", texts(definition.params) + PathVariables.sentValues(definition.pathVariables, in: definition.url)), ("Headers", texts(definition.headers)),
            ("Body", body), ("Auth", auth), ("Cookies", texts(definition.cookies)),
        ]
        var found: [(name: VariableName, sections: [String])] = []
        for (section, texts) in sections {
            for token in texts.flatMap(VariableTokens.ranges) {
                if let index = found.firstIndex(where: { $0.name == token.name }) {
                    if found[index].sections.last != section { found[index].sections.append(section) }
                } else {
                    found.append((token.name, [section]))
                }
            }
        }
        return found
    }
}
