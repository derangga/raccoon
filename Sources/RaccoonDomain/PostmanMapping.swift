import Foundation

/// What Postman Import will do, computed before anything is written: the Import sheet shows it,
/// and Import writes exactly it.
public struct ImportPlan: Equatable, Sendable {
    public var collections: [ImportCollection]
    public var environments: [ImportEnvironment]
    /// Added to Globals; none of these names is in Globals yet.
    public var globals: [ImportVariable]
    public var notes: [ImportNote]

    public init(collections: [ImportCollection], environments: [ImportEnvironment], globals: [ImportVariable], notes: [ImportNote]) {
        self.collections = collections
        self.environments = environments
        self.globals = globals
        self.notes = notes
    }
}

public struct ImportEnvironment: Equatable, Sendable {
    public var name: String
    public var variables: [ImportVariable]

    public init(name: String, variables: [ImportVariable]) {
        self.name = name
        self.variables = variables
    }
}

/// A planned Environment or Global. Unlike VariableEntry, a secret carries its value, for
/// SecretStore.set; it is not Codable, and the file gets `entry`, which holds none.
public struct ImportVariable: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case plain(String)
        case secret(String)
    }

    public var name: VariableName
    public var isEnabled: Bool
    public var value: Value

    public init(name: VariableName, isEnabled: Bool = true, value: Value) {
        self.name = name
        self.isEnabled = isEnabled
        self.value = value
    }

    /// What EnvironmentFile writes: a secret's value is not in it.
    public var entry: VariableEntry {
        switch value {
        case .plain(let text): VariableEntry(name: name, isEnabled: isEnabled, value: .plain(text))
        case .secret: VariableEntry(name: name, isEnabled: isEnabled, value: .secret)
        }
    }
}

public struct ImportCollection: Equatable, Sendable {
    public var name: String
    public var nodes: [ImportNode]

    public init(name: String, nodes: [ImportNode]) {
        self.name = name
        self.nodes = nodes
    }
}

/// A planned Folder or Request, in Postman's order. File names are chosen when it is written.
public indirect enum ImportNode: Equatable, Sendable {
    case folder(name: String, children: [ImportNode])
    case request(Request)
}

/// What was dropped or changed, and what it applies to by name. The count is `names.count`.
public struct ImportNote: Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        /// An item with neither `item` nor `request`; names the items.
        case itemsSkipped
        /// A `:name` segment's value was written into the path. Info: the bytes sent are the same.
        case pathVariable
        /// A `:name` segment with no value, kept as typed.
        case pathVariableEmpty(name: String)
        /// A binary (`file`) body, imported as none.
        case binaryBody
        /// A multipart file part whose `src` is not an absolute path: the send reports
        /// `fileMissing` until the file is picked again.
        case fileOnlyName(path: String)
        /// An Auth Raccoon has no equivalent for, imported as none; its settings are not kept.
        case authNotSupported(type: String)
        /// The Request inherited its auth from a Folder or the Collection, which is now written
        /// onto it. Info: what is sent is the same.
        case authInherited
        /// `{{$guid}}` and the like: not a VariableName, so undefined until it is replaced.
        case dynamicVariable(name: String)
        /// Pre-request and test scripts, the Request's own or a Folder's or the Collection's.
        case scriptsDropped
        /// Saved examples (`response`).
        case examplesDropped
        /// Names the Requests, Folders and Collections whose description was dropped.
        case descriptionsDropped
        /// A Collection or Environment planned under another name: taken, or not a file name.
        /// Names the old name.
        case renamed(from: String, to: String)
        /// A variable whose key is not a VariableName, dropped; names the keys.
        case variableNameInvalid
        /// A Global or Collection variable whose name Globals already has, which keeps its value;
        /// names the Variables.
        case globalSkipped
        /// Collection variables added to Globals. Info: Raccoon has no Collection Variables, and
        /// an Environment still wins over them, as in Postman. Names the Collections.
        case collectionVariables
    }

    public var kind: Kind
    /// The Requests, in plan order; a Folder's or Collection's name for its description, an
    /// item's for a skipped one, a Variable's for a Variable, a Collection's for its variables,
    /// the old name for a rename.
    public var names: [String]

    public init(_ kind: Kind, names: [String]) {
        self.kind = kind
        self.names = names
    }
}

/// Notes gathered while planning: one per kind, in the order first met.
private struct Notes {
    private var kinds: [ImportNote.Kind] = []
    private var names: [ImportNote.Kind: [String]] = [:]

    mutating func add(_ kind: ImportNote.Kind, _ name: String) {
        if names[kind] == nil { kinds.append(kind) }
        names[kind, default: []].append(name)
    }

    var all: [ImportNote] {
        kinds.map { ImportNote($0, names: names[$0] ?? []) }
    }
}

/// Postman Import's mapping half: PostmanFiles to an ImportPlan. Pure.
public enum PostmanMapping {
    /// `dataFolder`, `globals` and `environments` are what the Workspace already has: the names
    /// an imported Collection, Environment or Global must not take. `newID` makes each planned
    /// Request's RequestID. Collection variables are added to Globals before Globals files, so
    /// a Collection variable wins over a Global of the same name, as in Postman. `.notPostman`
    /// files are not planned: the Import sheet lists them.
    public static func plan(
        _ files: [PostmanFile], dataFolder: DataFolderIndex, globals: Globals, environments: [Environment],
        newID: () -> RequestID
    ) -> ImportPlan {
        var notes = Notes()
        var collections: [ImportCollection] = []
        var collectionNames = dataFolder.collections.map(\.name)
        var environmentNames = environments.map(\.name)
        var planned: [ImportEnvironment] = []
        var added: [ImportVariable] = []
        var globalNames = Set(globals.entries.map(\.name))
        /// Adds the new names to Globals; whether any was.
        func addGlobals(_ values: [PostmanVariable]) -> Bool {
            let count = added.count
            for variable in variables(values, notes: &notes) {
                if globalNames.insert(variable.name).inserted { added.append(variable) } else { notes.add(.globalSkipped, variable.name.rawValue) }
            }
            return added.count > count
        }
        for case .collection(let collection) in files {
            let name = name(collection.name, taken: &collectionNames, notes: &notes)
            if !(collection.description ?? "").isEmpty { notes.add(.descriptionsDropped, name) }
            collections.append(ImportCollection(name: name, nodes: nodes(
                collection.items, auth: effective(collection.auth, over: nil), scripts: hasScripts(collection.events),
                notes: &notes, newID: newID
            )))
            if addGlobals(collection.variables) { notes.add(.collectionVariables, name) }
        }
        for case .environment(let environment) in files {
            let name = name(environment.name, taken: &environmentNames, notes: &notes)
            planned.append(ImportEnvironment(name: name, variables: variables(environment.values, notes: &notes)))
        }
        for case .globals(let values) in files {
            _ = addGlobals(values)
        }
        return ImportPlan(collections: collections, environments: planned, globals: added, notes: notes.all)
    }

    /// A key with no name is no variable, so it is dropped without a note.
    private static func variables(_ values: [PostmanVariable], notes: inout Notes) -> [ImportVariable] {
        values.compactMap { value in
            guard let name = VariableName(value.key.trimmingCharacters(in: .whitespaces)) else {
                if !value.key.isEmpty { notes.add(.variableNameInvalid, value.key) }
                return nil
            }
            return ImportVariable(name: name, isEnabled: value.enabled, value: value.type == "secret" ? .secret(value.value) : .plain(value.value))
        }
    }

    /// `name` as a file name not in `taken`, ignoring case, which it then joins.
    private static func name(_ name: String, taken: inout [String], notes: inout Notes) -> String {
        let final = RequestFileName.unique(RequestFileName.sanitised(name), taken: Set(taken))
        taken.append(final)
        if final != name { notes.add(.renamed(from: name, to: final), name) }
        return final
    }

    /// `auth` is what the items inherit: the nearest Folder's or the Collection's. `scripts` is
    /// whether a Folder or the Collection above them has one, which Postman runs for each.
    private static func nodes(
        _ items: [PostmanItem], auth: PostmanAuth?, scripts: Bool, notes: inout Notes, newID: () -> RequestID
    ) -> [ImportNode] {
        items.compactMap { item in
            switch item {
            case .folder(let folder):
                if !(folder.description ?? "").isEmpty { notes.add(.descriptionsDropped, folder.name) }
                let children = nodes(
                    folder.items, auth: effective(folder.auth, over: auth), scripts: scripts || hasScripts(folder.events),
                    notes: &notes, newID: newID
                )
                return .folder(name: folder.name, children: children)
            case .request(let request):
                var kinds: [ImportNote.Kind] = []
                let definition = definition(request, inherited: auth, notes: &kinds)
                // A Request's file name is its name, so it needs one.
                let name = request.name.trimmingCharacters(in: .whitespaces).isEmpty
                    ? Tab.title(url: definition.url) ?? definition.method : request.name
                let planned = Request(id: newID(), name: name, definition: definition)
                kinds += dynamicVariables(planned.definition).map { .dynamicVariable(name: $0) }
                if scripts || hasScripts(request.events) { kinds.append(.scriptsDropped) }
                if request.responseCount > 0 { kinds.append(.examplesDropped) }
                if !(request.description ?? "").isEmpty { kinds.append(.descriptionsDropped) }
                var seen: Set<ImportNote.Kind> = []
                for kind in kinds where seen.insert(kind).inserted { notes.add(kind, name) }
                return .request(planned)
            case .other(let name):
                notes.add(.itemsSkipped, name)
                return nil
            }
        }
    }

    private static func definition(_ request: PostmanRequest, inherited: PostmanAuth?, notes: inout [ImportNote.Kind]) -> RequestDefinition {
        var (url, params) = url(request.url, notes: &notes)
        let isCookie = { (header: PostmanKeyValue) in header.key.caseInsensitiveCompare("Cookie") == .orderedSame }
        let cookies = request.headers.filter(isCookie).flatMap { header in
            CurlMapping.cookieRows(header.value).map { Row(name: $0.name, value: $0.value, isEnabled: !header.disabled) }
        }
        let body = request.body.map { body($0, notes: &notes) } ?? .none
        var headers = rows(request.headers.filter { !isCookie($0) })
        let postmanAuth = effective(request.auth, over: inherited)
        if effective(request.auth, over: nil) == nil, let postmanAuth, postmanAuth.type != "noauth" { notes.append(.authInherited) }
        let auth = auth(postmanAuth, headers: &headers, params: &params, notes: &notes)
        headers = Headers.contentType(headers, from: .none, to: body.type)
        return RequestDefinition(
            method: request.method.uppercased(), url: url, params: params, headers: headers, cookies: cookies, body: body, auth: auth,
            settings: RequestSettings(allowsInsecureTLS: request.strictSSL == false, followsRedirects: request.followRedirects ?? true)
        )
    }

    /// `raw` when present, else built from the parts; the fragment is never sent, so it is
    /// dropped. Params come from `query`, or for a string url from its own query.
    private static func url(_ url: PostmanURL, notes: inout [ImportNote.Kind]) -> (String, [Row]) {
        let scheme: String = url.protocol.map { $0 + "://" } ?? ""
        let port: String = url.port.map { ":" + $0 } ?? ""
        let path: String = url.path.map { "/" + $0.joined(separator: "/") } ?? ""
        let text = url.raw ?? scheme + (url.host ?? []).joined(separator: ".") + port + path
        let (base, pairs) = URLText.split(String(text.prefix { $0 != "#" }))
        let segments = base.split(separator: "/", omittingEmptySubsequences: false).map { segment -> Substring in
            guard segment.hasPrefix(":"), segment.count > 1 else { return segment }
            let name = String(segment.dropFirst())
            guard let value = url.variable.first(where: { $0.key == name })?.value, !value.isEmpty else {
                notes.append(.pathVariableEmpty(name: name))
                return segment
            }
            notes.append(.pathVariable)
            return Substring(value)
        }
        let params = url.query.isEmpty ? pairs : rows(url.query)
        return (segments.joined(separator: "/"), params)
    }

    /// Postman often exports `exec: [""]`: a blank script runs nothing, so it is not counted.
    private static func hasScripts(_ events: [PostmanEvent]) -> Bool {
        events.contains { !$0.exec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The `{{$name}}` references anywhere in what will be sent, in order, `{{ $name }}` included.
    private static func dynamicVariables(_ definition: RequestDefinition) -> [String] {
        let rows = definition.params + definition.headers + definition.cookies
        var texts = [definition.url] + rows.flatMap { [$0.name, $0.value] }
        switch definition.body {
        case .none: break
        case .raw(_, let text): texts.append(text)
        case .formURLEncoded(let rows): texts += rows.flatMap { [$0.name, $0.value] }
        case .multipart(let parts):
            texts += parts.flatMap { part -> [String] in
                switch part.content {
                case .text(let value): [part.name, value]
                case .file(let path): [part.name, path]
                }
            }
        }
        switch definition.auth {
        case .none: break
        case .basic(let user, let password): texts += [user, password]
        case .bearer(let token): texts.append(token)
        }
        return texts.flatMap { $0.matches(of: /\{\{\s*(\$[^{}\s]*)\s*\}\}/).map { String($0.output.1) } }
    }

    /// `inherit` is the same as no auth: the parent's.
    private static func effective(_ own: PostmanAuth?, over inherited: PostmanAuth?) -> PostmanAuth? {
        own.flatMap { $0.type == "inherit" ? nil : $0 } ?? inherited
    }

    /// apikey is a header or a Param with that name and value: the same bytes on the wire.
    private static func auth(_ auth: PostmanAuth?, headers: inout [Row], params: inout [Row], notes: inout [ImportNote.Kind]) -> Auth {
        guard let auth else { return .none }
        let parameter = { (key: String) in auth.parameters[key] ?? "" }
        switch auth.type {
        case "noauth":
            return .none
        case "basic":
            return .basic(user: parameter("username"), password: parameter("password"))
        case "bearer":
            return .bearer(token: parameter("token"))
        case "apikey":
            // A header or a Param needs a name.
            guard !parameter("key").isEmpty else { return .none }
            let row = Row(name: parameter("key"), value: parameter("value"))
            if parameter("in") == "query" { params.append(row) } else { headers.append(row) }
            return .none
        default:
            notes.append(.authNotSupported(type: auth.type))
            return .none
        }
    }

    /// Empty is none: Postman exports `{"mode": "raw", "raw": ""}` on plain GETs.
    private static func body(_ body: PostmanBody, notes: inout [ImportNote.Kind]) -> Body {
        switch body {
        case .raw("", _), .graphql("", _):
            return .none
        case .raw(let text, let language):
            return .raw(language == "json" ? .json : language == "xml" ? .xml : .text, text)
        case .urlencoded(let pairs):
            let rows = rows(pairs)
            return rows.isEmpty ? .none : .formURLEncoded(rows)
        case .formdata(let parameters):
            let parameters = parameters.filter { !$0.key.isEmpty || $0.content != .text("") }
            if parameters.isEmpty { return .none }
            return .multipart(parameters.flatMap { parameter -> [Part] in
                switch parameter.content {
                case .text(let value):
                    return [Part(name: parameter.key, isEnabled: !parameter.disabled, content: .text(value))]
                case .file(let src):
                    return (src.isEmpty ? [""] : src).map { path in
                        if !path.hasPrefix("/") { notes.append(.fileOnlyName(path: path)) }
                        return Part(name: parameter.key, isEnabled: !parameter.disabled, content: .file(path: path))
                    }
                }
            })
        case .graphql(let query, let variables):
            let encoded = (try? JSONSerialization.data(withJSONObject: query, options: [.fragmentsAllowed, .withoutEscapingSlashes]))
                .map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
            let trimmed = variables.trimmingCharacters(in: .whitespacesAndNewlines)
            return .raw(.json, #"{"query":"# + encoded + (trimmed.isEmpty ? "" : #","variables":"# + trimmed) + "}")
        case .file:
            notes.append(.binaryBody)
            return .none
        }
    }

    /// An entry with neither key nor value is no row: there is nothing to send, as the URL bar
    /// skips an empty pair.
    private static func rows(_ pairs: [PostmanKeyValue]) -> [Row] {
        pairs.filter { !$0.key.isEmpty || !$0.value.isEmpty }.map(row)
    }

    private static func row(_ pair: PostmanKeyValue) -> Row {
        Row(name: pair.key, value: pair.value, isEnabled: !pair.disabled)
    }
}
