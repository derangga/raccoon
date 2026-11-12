import Foundation

/// What a Request and a Draft share, and the only thing a Tab edits.
public struct RequestDefinition: Equatable, Sendable {
    /// Uppercased. Not an enum: `curl -X PURGE` is a real method.
    public var method: String
    /// The text before `?`. The query is always rendered from `params`.
    public var url: String
    public var params: [Row]
    /// Path Variable name -> value, without the `:`. Holds only non-empty values: `""` is absent,
    /// so clearing a value gives back an equal definition. The URL says which names exist.
    public var pathVariables: [String: String]
    public var headers: [Row]
    /// Request Cookies.
    public var cookies: [Row]
    public var body: Body
    public var auth: Auth
    public var settings: RequestSettings
    /// The Request's Docs, markdown, "" for none. Never sent: the resolver drops it (docs.md).
    public var docs: String

    public init(
        method: String, url: String, params: [Row], pathVariables: [String: String] = [:],
        headers: [Row], cookies: [Row],
        body: Body, auth: Auth, settings: RequestSettings, docs: String = ""
    ) {
        self.method = method
        self.url = url
        self.params = params
        self.pathVariables = pathVariables
        self.headers = headers
        self.cookies = cookies
        self.body = body
        self.auth = auth
        self.settings = settings
        self.docs = docs
    }

    /// The empty Draft.
    public static let empty = RequestDefinition(
        method: "GET", url: "", params: [], headers: [], cookies: [],
        body: .none, auth: .none,
        settings: RequestSettings(allowsInsecureTLS: false, followsRedirects: false)
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
    /// The three below change nothing while `followsRedirects` is off (sending.md).
    public var followsOriginalMethod: Bool
    public var followsAuthorizationHeader: Bool
    /// The Redirect Limit. Assigning out of range clamps instead of failing, so no caller has
    /// to range-check: the file, Postman Import, Curl Import and the pane all land in range.
    public var maxRedirects: Int {
        didSet { maxRedirects = Self.maxRedirectsRange.clamped(maxRedirects) }
    }

    /// The Request Timeout in seconds, nil for the transport's default. Clamped like the above.
    public var timeoutSeconds: Int? {
        didSet { timeoutSeconds = timeoutSeconds.map(Self.timeoutRange.clamped) }
    }

    /// URLSession stops at 20 itself (environment-facts.md), so a larger limit is a promise
    /// Raccoon cannot keep.
    public static let maxRedirectsRange = 0...20
    public static let timeoutRange = 1...3600

    public init(
        allowsInsecureTLS: Bool, followsRedirects: Bool,
        followsOriginalMethod: Bool = false, followsAuthorizationHeader: Bool = false,
        maxRedirects: Int = maxRedirectsRange.upperBound, timeoutSeconds: Int? = nil
    ) {
        self.allowsInsecureTLS = allowsInsecureTLS
        self.followsRedirects = followsRedirects
        self.followsOriginalMethod = followsOriginalMethod
        self.followsAuthorizationHeader = followsAuthorizationHeader
        // Clamped here as well as in didSet: a didSet does not run on an init's own assignment.
        self.maxRedirects = Self.maxRedirectsRange.clamped(maxRedirects)
        self.timeoutSeconds = timeoutSeconds.map(Self.timeoutRange.clamped)
    }
}

extension ClosedRange where Bound == Int {
    /// `value` pulled into the range, which is never empty.
    public func clamped(_ value: Int) -> Int {
        Swift.min(Swift.max(value, lowerBound), upperBound)
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

/// A RequestDefinition with every `{{name}}` substituted and every Disabled Row dropped, and
/// the URL built once from its base and percent-encoded params.
/// The init is internal so only `VariableResolver` can build one: a request with an
/// Undefined Variable never becomes a type the transport accepts.
public struct ResolvedRequest: Equatable, Sendable {
    public let definition: RequestDefinition
    public let url: URL

    init(definition: RequestDefinition, url: URL) {
        self.definition = definition
        self.url = url
    }
}
