import Foundation

/// session.json's format. The bytes go through SessionStore; this is the only code that reads them.
public enum SessionFile {
    private struct Header: Decodable {
        var version: Int
    }

    private struct File: Codable {
        var version = 1
        var tabs: [TabJSON]?
        var selected: UUID?
        var activeEnvironment: String?
    }

    private struct TabJSON: Codable {
        var id: UUID
        /// Absent for a Draft.
        var requestID: UUID?
        var definition: DefinitionJSON
        var baseline: DefinitionJSON?
    }

    /// Optional wherever absence has a default (boundary.md): a hand-trimmed file still opens.
    private struct DefinitionJSON: Codable {
        var method: String
        var url: String
        var params: [RowJSON]?
        var headers: [RowJSON]?
        var cookies: [RowJSON]?
        var body: BodyJSON?
        var auth: AuthJSON?
        var settings: SettingsJSON?
    }

    private struct RowJSON: Codable {
        var name: String
        var value: String
        var isEnabled: Bool?
    }

    /// `type` is raw, form or multipart; the other keys belong to one of them.
    private struct BodyJSON: Codable {
        var type: String
        var kind: String?
        var text: String?
        var rows: [RowJSON]?
        var parts: [PartJSON]?
    }

    /// Exactly one of `text` and `file`.
    private struct PartJSON: Codable {
        var name: String
        var isEnabled: Bool?
        var text: String?
        var file: String?
    }

    /// `type` is basic or bearer.
    private struct AuthJSON: Codable {
        var type: String
        var user: String?
        var password: String?
        var token: String?
    }

    private struct SettingsJSON: Codable {
        var allowsInsecureTLS: Bool?
        var followsRedirects: Bool?
    }

    private struct Malformed: Error {
        let reason: String
    }

    public static func encode(_ session: Session) -> Data {
        let file = File(
            tabs: session.tabs.map { tab in
                let requestID: UUID? = if case .request(let id) = tab.source { id.rawValue } else { nil }
                return TabJSON(id: tab.id.rawValue, requestID: requestID, definition: json(tab.definition),
                               baseline: tab.baseline.map(json))
            },
            selected: session.selected?.rawValue,
            activeEnvironment: session.activeEnvironment
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Only strings, numbers and bools: encoding cannot fail.
        return try! encoder.encode(file)
    }

    /// `version` is read first: an unknown one is undecodable, never guessed at.
    public static func decode(_ data: Data) throws(StoreError) -> Session {
        do {
            let version = try JSONDecoder().decode(Header.self, from: data).version
            guard version == 1 else { throw Malformed(reason: "unknown version \(version)") }
            let file = try JSONDecoder().decode(File.self, from: data)
            return Session(
                tabs: try (file.tabs ?? []).map { tab in
                    TabSnapshot(id: TabID(tab.id), source: tab.requestID.map { .request(RequestID($0)) } ?? .draft,
                                definition: try definition(tab.definition), baseline: try tab.baseline.map(definition))
                },
                selected: file.selected.map(TabID.init),
                activeEnvironment: file.activeEnvironment
            )
        } catch let error as Malformed {
            throw .undecodable(path: "session.json", reason: error.reason)
        } catch {
            throw .undecodable(path: "session.json", reason: String(describing: error))
        }
    }

    private static func json(_ definition: RequestDefinition) -> DefinitionJSON {
        let body: BodyJSON? = switch definition.body {
        case .none: nil
        case .raw(let kind, let text): BodyJSON(type: "raw", kind: rawKinds.first { $0.1 == kind }?.0, text: text)
        case .formURLEncoded(let rows): BodyJSON(type: "form", rows: rows.map(json))
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
        return DefinitionJSON(
            method: definition.method, url: definition.url,
            params: definition.params.map(json), headers: definition.headers.map(json), cookies: definition.cookies.map(json),
            body: body, auth: auth,
            settings: SettingsJSON(allowsInsecureTLS: definition.settings.allowsInsecureTLS,
                                   followsRedirects: definition.settings.followsRedirects)
        )
    }

    private static func json(_ row: Row) -> RowJSON {
        RowJSON(name: row.name, value: row.value, isEnabled: row.isEnabled)
    }

    private static let rawKinds: [(String, RawKind)] = [("json", .json), ("text", .text), ("xml", .xml)]

    private static func definition(_ json: DefinitionJSON) throws(Malformed) -> RequestDefinition {
        let empty = RequestDefinition.empty
        return RequestDefinition(
            method: json.method, url: json.url,
            params: (json.params ?? []).map(row), headers: (json.headers ?? []).map(row), cookies: (json.cookies ?? []).map(row),
            body: try json.body.map(body) ?? .none,
            auth: try json.auth.map(auth) ?? .none,
            settings: RequestSettings(
                allowsInsecureTLS: json.settings?.allowsInsecureTLS ?? empty.settings.allowsInsecureTLS,
                followsRedirects: json.settings?.followsRedirects ?? empty.settings.followsRedirects
            )
        )
    }

    private static func row(_ json: RowJSON) -> Row {
        Row(name: json.name, value: json.value, isEnabled: json.isEnabled ?? true)
    }

    private static func body(_ json: BodyJSON) throws(Malformed) -> Body {
        switch json.type {
        case "raw":
            guard let kind = rawKinds.first(where: { $0.0 == json.kind })?.1, let text = json.text
            else { throw Malformed(reason: "a raw body needs a kind of json, text or xml, and text") }
            return .raw(kind, text)
        case "form":
            return .formURLEncoded((json.rows ?? []).map(row))
        case "multipart":
            return .multipart(try (json.parts ?? []).map { part throws(Malformed) in
                let content: Part.Content
                switch (part.text, part.file) {
                case (let text?, nil): content = .text(text)
                case (nil, let path?): content = .file(path: path)
                default: throw Malformed(reason: "multipart part \"\(part.name)\" needs one of text and file")
                }
                return Part(name: part.name, isEnabled: part.isEnabled ?? true, content: content)
            })
        default:
            throw Malformed(reason: "unknown body type \"\(json.type)\"")
        }
    }

    private static func auth(_ json: AuthJSON) throws(Malformed) -> Auth {
        switch (json.type, json.user, json.password, json.token) {
        case ("basic", let user?, let password?, _): .basic(user: user, password: password)
        case ("bearer", _, _, let token?): .bearer(token: token)
        default: throw Malformed(reason: "auth of type \"\(json.type)\" is missing its fields or unknown")
        }
    }
}
