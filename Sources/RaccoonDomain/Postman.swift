/// A Postman export file as PostmanImporter read it, in Postman's own terms (`key`, `disabled`,
/// `mode`, `listen`). PostmanMapping turns it into Raccoon's shapes; nothing here is one.
public enum PostmanFile: Equatable, Sendable {
    case collection(PostmanCollection)
    case environment(PostmanEnvironment)
    /// Globals carry a name in the file, but Raccoon has one set of Globals per Workspace.
    case globals([PostmanVariable])
    case notPostman
}

public struct PostmanCollection: Equatable, Sendable {
    /// `info.name`.
    public var name: String
    /// `info.description`.
    public var description: String?
    public var items: [PostmanItem]
    public var auth: PostmanAuth?
    public var events: [PostmanEvent]
    public var variables: [PostmanVariable]

    public init(
        name: String, description: String? = nil, items: [PostmanItem], auth: PostmanAuth? = nil,
        events: [PostmanEvent] = [], variables: [PostmanVariable] = []
    ) {
        self.name = name
        self.description = description
        self.items = items
        self.auth = auth
        self.events = events
        self.variables = variables
    }
}

/// An entry of an `item` array, in order: a folder has an `item` array, a request a `request`.
public enum PostmanItem: Equatable, Sendable {
    case folder(PostmanFolder)
    case request(PostmanRequest)
    /// Neither `item` nor `request`: skipped and counted, not a failure.
    case other(name: String)
}

public struct PostmanFolder: Equatable, Sendable {
    public var name: String
    public var description: String?
    public var items: [PostmanItem]
    /// nil when absent, which Postman reads as inherit, like `type: "inherit"`.
    public var auth: PostmanAuth?
    public var events: [PostmanEvent]

    public init(name: String, description: String? = nil, items: [PostmanItem], auth: PostmanAuth? = nil, events: [PostmanEvent] = []) {
        self.name = name
        self.description = description
        self.items = items
        self.auth = auth
        self.events = events
    }
}

/// A request item: the item's own keys and its `request` object's, in one value.
public struct PostmanRequest: Equatable, Sendable {
    public var name: String
    /// `request.description`, or the item's when the request has none.
    public var description: String?
    /// "GET" when absent.
    public var method: String
    public var url: PostmanURL
    public var headers: [PostmanKeyValue]
    public var body: PostmanBody?
    /// nil when absent, which Postman reads as inherit, like `type: "inherit"`.
    public var auth: PostmanAuth?
    /// `protocolProfileBehavior.followRedirects`.
    public var followRedirects: Bool?
    /// `protocolProfileBehavior.strictSSL`.
    public var strictSSL: Bool?
    public var events: [PostmanEvent]
    /// The saved examples in `response`. Raccoon keeps none, so only their count is read.
    public var responseCount: Int

    public init(
        name: String, description: String? = nil, method: String = "GET", url: PostmanURL = PostmanURL(),
        headers: [PostmanKeyValue] = [], body: PostmanBody? = nil, auth: PostmanAuth? = nil,
        followRedirects: Bool? = nil, strictSSL: Bool? = nil, events: [PostmanEvent] = [], responseCount: Int = 0
    ) {
        self.name = name
        self.description = description
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.auth = auth
        self.followRedirects = followRedirects
        self.strictSSL = strictSSL
        self.events = events
        self.responseCount = responseCount
    }
}

/// `url` as a string is `raw` alone. As an object, `host` and `path` may each be a string or an
/// array; a string is split, on "." and "/", so both arrive as the segments Postman shows.
public struct PostmanURL: Equatable, Sendable {
    public var raw: String?
    public var `protocol`: String?
    public var host: [String]?
    public var port: String?
    public var path: [String]?
    public var query: [PostmanKeyValue]
    /// Path variables: the values of `:name` segments.
    public var variable: [PostmanKeyValue]
    public var hash: String?

    public init(
        raw: String? = nil, protocol: String? = nil, host: [String]? = nil, port: String? = nil, path: [String]? = nil,
        query: [PostmanKeyValue] = [], variable: [PostmanKeyValue] = [], hash: String? = nil
    ) {
        self.raw = raw
        self.protocol = `protocol`
        self.host = host
        self.port = port
        self.path = path
        self.query = query
        self.variable = variable
        self.hash = hash
    }
}

/// A header, query parameter, path variable or urlencoded field. A `null` or absent value is "".
public struct PostmanKeyValue: Equatable, Sendable {
    public var key: String
    public var value: String
    public var disabled: Bool

    public init(key: String, value: String, disabled: Bool = false) {
        self.key = key
        self.value = value
        self.disabled = disabled
    }
}

/// `body` by its `mode`. An unknown mode is no body.
public enum PostmanBody: Equatable, Sendable {
    /// `options.raw.language`: json, xml, text, html, javascript, or nil.
    case raw(String, language: String?)
    case urlencoded([PostmanKeyValue])
    case formdata([PostmanFormParameter])
    /// `variables` is the text Postman stores; an object there is written out as JSON.
    case graphql(query: String, variables: String)
    /// A binary body: `file.src`, often only a file name.
    case file(src: String?)
}

public struct PostmanFormParameter: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case text(String)
        /// `src` is a path, a list of them, or absent; Postman often keeps only a file name.
        case file(src: [String])
    }

    public var key: String
    public var content: Content
    public var disabled: Bool

    public init(key: String, content: Content, disabled: Bool = false) {
        self.key = key
        self.content = content
        self.disabled = disabled
    }
}

/// `type` as Postman spells it (noauth, inherit, basic, bearer, apikey, oauth2, …) and that
/// type's parameters. Postman writes them as `[{key, value}]`; v2.0 also as an object.
public struct PostmanAuth: Equatable, Sendable {
    public var type: String
    public var parameters: [String: String]

    public init(type: String, parameters: [String: String] = [:]) {
        self.type = type
        self.parameters = parameters
    }
}

/// A pre-request or test script: `listen` is "prerequest" or "test", `exec` joined by lines.
public struct PostmanEvent: Equatable, Sendable {
    public var listen: String
    public var exec: String

    public init(listen: String, exec: String) {
        self.listen = listen
        self.exec = exec
    }
}

public struct PostmanEnvironment: Equatable, Sendable {
    public var name: String
    public var values: [PostmanVariable]

    public init(name: String, values: [PostmanVariable]) {
        self.name = name
        self.values = values
    }
}

/// An Environment or Globals value, or a collection `variable`. A collection variable's
/// `disabled` is read as `enabled: false`. Values of any JSON type arrive as text.
public struct PostmanVariable: Equatable, Sendable {
    public var key: String
    public var value: String
    public var enabled: Bool
    /// "secret" for a secret; "default", "text" or nil otherwise.
    public var type: String?

    public init(key: String, value: String, enabled: Bool = true, type: String? = nil) {
        self.key = key
        self.value = value
        self.enabled = enabled
        self.type = type
    }
}
