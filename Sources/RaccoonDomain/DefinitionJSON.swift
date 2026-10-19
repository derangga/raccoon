import Foundation

/// A RequestDefinition as JSON, shared by the Session file and the Request files so the two never
/// disagree. Optional wherever absence has a default (boundary.md): a hand-trimmed file still opens.
struct DefinitionJSON: Codable {
    var method: String
    var url: String
    var params: [RowJSON]?
    var headers: [RowJSON]?
    var cookies: [RowJSON]?
    var body: BodyJSON?
    var auth: AuthJSON?
    var settings: SettingsJSON?

    struct RowJSON: Codable {
        var name: String
        var value: String
        var isEnabled: Bool?
    }

    /// `type` is raw, form or multipart; the other keys belong to one of them.
    struct BodyJSON: Codable {
        var type: String
        var kind: String?
        var text: String?
        var rows: [RowJSON]?
        var parts: [PartJSON]?
    }

    /// Exactly one of `text` and `file`.
    struct PartJSON: Codable {
        var name: String
        var isEnabled: Bool?
        var text: String?
        var file: String?
    }

    /// `type` is basic or bearer.
    struct AuthJSON: Codable {
        var type: String
        var user: String?
        var password: String?
        var token: String?
    }

    struct SettingsJSON: Codable {
        var allowsInsecureTLS: Bool?
        var followsRedirects: Bool?
    }

    init(_ definition: RequestDefinition) {
        let body: BodyJSON? = switch definition.body {
        case .none: nil
        case .raw(let kind, let text): BodyJSON(type: "raw", kind: Self.rawKinds.first { $0.1 == kind }?.0, text: text)
        case .formURLEncoded(let rows): BodyJSON(type: "form", rows: rows.map(RowJSON.init))
        case .multipart(let parts): BodyJSON(type: "multipart", parts: parts.map { part in
            switch part.content {
            case .text(let text): PartJSON(name: part.name, isEnabled: part.isEnabled, text: text)
            case .file(let path): PartJSON(name: part.name, isEnabled: part.isEnabled, file: path)
            }
        })
        }
        let auth: AuthJSON? = switch definition.auth {
        case .none: nil
        case .basic(let user, let password): AuthJSON(type: "basic", user: user, password: password)
        case .bearer(let token): AuthJSON(type: "bearer", token: token)
        }
        self.init(
            method: definition.method, url: definition.url,
            params: Self.rows(definition.params), headers: Self.rows(definition.headers),
            cookies: Self.rows(definition.cookies),
            body: body, auth: auth,
            settings: SettingsJSON(allowsInsecureTLS: definition.settings.allowsInsecureTLS,
                                   followsRedirects: definition.settings.followsRedirects)
        )
    }

    /// Left out when empty: absence means no rows, and Foundation prints `[]` over three lines.
    private static func rows(_ rows: [Row]) -> [RowJSON]? {
        rows.isEmpty ? nil : rows.map(RowJSON.init)
    }

    init(method: String, url: String, params: [RowJSON]?, headers: [RowJSON]?, cookies: [RowJSON]?,
         body: BodyJSON?, auth: AuthJSON?, settings: SettingsJSON?) {
        (self.method, self.url, self.params, self.headers, self.cookies) = (method, url, params, headers, cookies)
        (self.body, self.auth, self.settings) = (body, auth, settings)
    }

    func definition() throws(Malformed) -> RequestDefinition {
        let empty = RequestDefinition.empty
        return RequestDefinition(
            method: method, url: url,
            params: (params ?? []).map(\.row), headers: (headers ?? []).map(\.row), cookies: (cookies ?? []).map(\.row),
            body: try body.map { json throws(Malformed) in try json.body() } ?? .none,
            auth: try auth.map { json throws(Malformed) in try json.auth() } ?? .none,
            settings: RequestSettings(
                allowsInsecureTLS: settings?.allowsInsecureTLS ?? empty.settings.allowsInsecureTLS,
                followsRedirects: settings?.followsRedirects ?? empty.settings.followsRedirects
            )
        )
    }

    static let rawKinds: [(String, RawKind)] = [("json", .json), ("text", .text), ("xml", .xml)]
}

/// A file that is JSON but not one Raccoon can read; `reason` says what is wrong in it.
struct Malformed: Error {
    let reason: String
}

extension DefinitionJSON.RowJSON {
    init(_ row: Row) {
        self.init(name: row.name, value: row.value, isEnabled: row.isEnabled)
    }

    var row: Row { Row(name: name, value: value, isEnabled: isEnabled ?? true) }
}

extension DefinitionJSON.BodyJSON {
    func body() throws(Malformed) -> Body {
        switch type {
        case "raw":
            guard let kind = DefinitionJSON.rawKinds.first(where: { $0.0 == self.kind })?.1, let text
            else { throw Malformed(reason: "a raw body needs a kind of json, text or xml, and text") }
            return .raw(kind, text)
        case "form":
            return .formURLEncoded((rows ?? []).map(\.row))
        case "multipart":
            return .multipart(try (parts ?? []).map { part throws(Malformed) in
                let content: Part.Content
                switch (part.text, part.file) {
                case (let text?, nil): content = .text(text)
                case (nil, let path?): content = .file(path: path)
                default: throw Malformed(reason: "multipart part \"\(part.name)\" needs one of text and file")
                }
                return Part(name: part.name, isEnabled: part.isEnabled ?? true, content: content)
            })
        default:
            throw Malformed(reason: "unknown body type \"\(type)\"")
        }
    }
}

extension DefinitionJSON.AuthJSON {
    func auth() throws(Malformed) -> Auth {
        switch (type, user, password, token) {
        case ("basic", let user?, let password?, _): .basic(user: user, password: password)
        case ("bearer", _, _, let token?): .bearer(token: token)
        default: throw Malformed(reason: "auth of type \"\(type)\" is missing its fields or unknown")
        }
    }
}
