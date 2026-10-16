/// What a Request and a Draft share, and the only thing a Tab edits.
public struct RequestDefinition: Equatable, Sendable {
    /// Uppercased. Not an enum: `curl -X PURGE` is a real method.
    public var method: String
    /// The text before `?`. The query is always rendered from `params`.
    public var url: String
    public var params: [Row]
    public var headers: [Row]
    /// Request Cookies.
    public var cookies: [Row]
    public var body: Body
    public var auth: Auth
    public var settings: RequestSettings

    public init(
        method: String, url: String, params: [Row], headers: [Row], cookies: [Row],
        body: Body, auth: Auth, settings: RequestSettings
    ) {
        self.method = method
        self.url = url
        self.params = params
        self.headers = headers
        self.cookies = cookies
        self.body = body
        self.auth = auth
        self.settings = settings
    }

    /// The empty Draft.
    public static let empty = RequestDefinition(
        method: "GET", url: "", params: [], headers: [], cookies: [],
        body: .none, auth: .none,
        settings: RequestSettings(allowsInsecureTLS: false, followsRedirects: false, requestsCompression: false)
    )
}

/// A Disabled Row is `isEnabled == false`: it stays in place and is not sent.
public struct Row: Equatable, Sendable {
    public var name: String
    public var value: String
    public var isEnabled: Bool

    public init(name: String, value: String, isEnabled: Bool = true) {
        self.name = name
        self.value = value
        self.isEnabled = isEnabled
    }
}

public enum RawKind: Equatable, Sendable {
    case json, text, xml
}

public enum Body: Equatable, Sendable {
    case none
    case raw(RawKind, String)
    case formURLEncoded([Row])
    case multipart([Part])
}

public struct Part: Equatable, Sendable {
    public enum Content: Equatable, Sendable {
        case text(String)
        case file(path: String)
    }

    public var name: String
    public var isEnabled: Bool
    public var content: Content

    public init(name: String, isEnabled: Bool = true, content: Content) {
        self.name = name
        self.isEnabled = isEnabled
        self.content = content
    }
}

public enum Auth: Equatable, Sendable {
    case none
    case basic(user: String, password: String)
    case bearer(token: String)
}

public struct RequestSettings: Equatable, Sendable {
    public var allowsInsecureTLS: Bool
    public var followsRedirects: Bool
    public var requestsCompression: Bool

    public init(allowsInsecureTLS: Bool, followsRedirects: Bool, requestsCompression: Bool) {
        self.allowsInsecureTLS = allowsInsecureTLS
        self.followsRedirects = followsRedirects
        self.requestsCompression = requestsCompression
    }
}

/// One file in the Data Folder.
public struct Request: Equatable, Sendable {
    public let id: RequestID
    public var name: String
    public var definition: RequestDefinition

    public init(id: RequestID, name: String, definition: RequestDefinition) {
        self.id = id
        self.name = name
        self.definition = definition
    }
}

/// A RequestDefinition with every `{{name}}` substituted and every Disabled Row dropped.
/// The init is internal so only `VariableResolver` can build one: a request with an
/// Undefined Variable never becomes a type the transport accepts.
public struct ResolvedRequest: Equatable, Sendable {
    public let definition: RequestDefinition

    init(definition: RequestDefinition) {
        self.definition = definition
    }
}
