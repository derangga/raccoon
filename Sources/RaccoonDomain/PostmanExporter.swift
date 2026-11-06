import Foundation

/// A Collection as Postman Export reads it: every Request decoded from its file, in sidebar order.
public struct ExportCollection: Equatable, Sendable {
    public var name: String
    public var nodes: [ExportNode]

    public init(name: String, nodes: [ExportNode]) {
        self.name = name
        self.nodes = nodes
    }
}

public indirect enum ExportNode: Equatable, Sendable {
    case folder(name: String, children: [ExportNode])
    case request(Request)
}

/// What Include secret values read from the SecretStore, held from the save panel's return to the
/// write. Not Codable: a secret's value goes from memory to the one file and is dropped.
public struct EnvironmentSecrets: Equatable, Sendable {
    public var values: [VariableName: String]
    /// Secrets whose Keychain read failed: written as "" like the rest, and named to the user.
    public var unreadable: [VariableName]

    public init(values: [VariableName: String], unreadable: [VariableName]) {
        self.values = values
        self.unreadable = unreadable
    }

    public static let none = EnvironmentSecrets(values: [:], unreadable: [])
}

/// Postman Export's writing half: Postman Import's table read backwards. Pure: the id is passed
/// in, and the order is the one given. Where Raccoon has less than Postman, the key is not written.
public enum PostmanExporter {
    /// Collection v2.1 JSON: sorted keys, two-space indent, a final newline, as Request files are,
    /// so two exports with one `id` are byte-equal.
    public static func collection(_ collection: ExportCollection, id: UUID) -> Data {
        let file = Root(
            info: Info(name: collection.name, id: id.uuidString.lowercased(), schema: schema),
            item: collection.nodes.map(item)
        )
        return encode(file)
    }

    /// Postman Environment JSON, encoded as `collection` is. A Secret Variable's value is the one in
    /// `secrets`, or "" when it has none: the file says it was never typed.
    public static func environment(
        _ environment: Environment, secrets: EnvironmentSecrets, id: UUID, exportedAt: Date, version: String
    ) -> Data {
        let file = EnvFile(
            id: id.uuidString.lowercased(), name: environment.name,
            exportedAt: exportedAt.ISO8601Format(.init(includingFractionalSeconds: true)),
            using: "Raccoon/\(version)",
            values: environment.entries.map { entry in
                switch entry.value {
                case .plain(let value): EnvValue(key: entry.name.rawValue, value: value, type: "default", enabled: entry.isEnabled)
                case .secret:
                    EnvValue(key: entry.name.rawValue, value: secrets.values[entry.name] ?? "", type: "secret", enabled: entry.isEnabled)
                }
            }
        )
        return encode(file)
    }

    /// Sorted keys, two-space indent, a final newline, as Request files are.
    private static func encode<T: Encodable>(_ file: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        // Encoding Strings, Bools and arrays of them cannot fail.
        return try! encoder.encode(file) + Data("\n".utf8)
    }

    private static let schema = "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"

    private static func item(_ node: ExportNode) -> Item {
        switch node {
        case .folder(let name, let children):
            return Item(name: name, item: children.map(item))
        case .request(let request):
            let definition = request.definition
            return Item(
                name: request.name, request: wire(definition), response: [],
                protocolProfileBehavior: Behavior(
                    followRedirects: definition.settings.followsRedirects,
                    strictSSL: definition.settings.allowsInsecureTLS ? false : nil,
                    // Postman drops a GET or HEAD body unless told to keep it.
                    disableBodyPruning: ["GET", "HEAD"].contains(definition.method) && definition.body != .none ? true : nil
                )
            )
        }
    }

    private static func wire(_ definition: RequestDefinition) -> Req {
        Req(
            method: definition.method, url: url(definition), header: headers(definition),
            body: body(definition.body), auth: auth(definition.auth)
        )
    }

    /// The parts come from `url` alone, split only outside `{{ }}`; `raw` is the URL bar's text.
    private static func url(_ definition: RequestDefinition) -> WireURL {
        let text = definition.url
        var url = WireURL(raw: URLText.join(text, params: definition.params))
        var rest = text
        let scheme = split(text, on: "://")
        if scheme.count > 1, !scheme[0].isEmpty, !scheme[0].contains("/") {
            url.scheme = scheme[0]
            rest = scheme.dropFirst().joined(separator: "://")
        }
        let segments = split(rest, on: "/")
        var host = split(segments[0], on: ":")
        if host.count > 1, let port = host.last, !port.isEmpty, port.allSatisfy(\.isASCIIDigit) {
            url.port = host.removeLast()
        }
        if !segments[0].isEmpty { url.host = split(host.joined(separator: ":"), on: ".") }
        if segments.count > 1 { url.path = Array(segments.dropFirst()) }
        if !definition.params.isEmpty { url.query = definition.params.map(keyValue) }
        let names = PathVariables.names(in: text)
        if !names.isEmpty { url.variable = names.map { KeyValue(key: $0, value: definition.pathVariables[$0] ?? "") } }
        return url
    }

    private static func split(_ text: String, on separator: String) -> [String] {
        URLText.outsideVariables(text) { String($0).replacing(separator, with: "\u{0}") }.components(separatedBy: "\u{0}")
    }

    /// The rows, then the Request Cookies: each run of one kind is one `Cookie` header.
    private static func headers(_ definition: RequestDefinition) -> [KeyValue] {
        var runs: [[Row]] = []
        for cookie in definition.cookies {
            if let last = runs.last?.last, last.isEnabled == cookie.isEnabled { runs[runs.count - 1].append(cookie) } else { runs.append([cookie]) }
        }
        return definition.headers.map(keyValue) + runs.map { run in
            KeyValue(key: "Cookie", value: run.map { "\($0.name)=\($0.value)" }.joined(separator: "; "), disabled: run[0].isEnabled ? nil : true)
        }
    }

    private static func body(_ body: Body) -> WireBody? {
        switch body {
        case .none:
            return nil
        case .raw(let kind, let text):
            let language = switch kind { case .json: "json"; case .xml: "xml"; case .text: "text" }
            return WireBody(mode: "raw", raw: text, options: RawOptions(raw: Language(language: language)))
        case .formURLEncoded(let rows):
            return WireBody(mode: "urlencoded", urlencoded: rows.map(keyValue))
        case .multipart(let parts):
            return WireBody(mode: "formdata", formdata: parts.map { part in
                switch part.content {
                case .text(let value): FormField(key: part.name, value: value, type: "text", disabled: part.isEnabled ? nil : true)
                case .file(let path): FormField(key: part.name, type: "file", src: path, disabled: part.isEnabled ? nil : true)
                }
            })
        }
    }

    /// `noauth` on every Request: an item with no `auth` inherits in Postman.
    private static func auth(_ auth: Auth) -> WireAuth {
        switch auth {
        case .none:
            return WireAuth(type: "noauth")
        case .basic(let user, let password):
            return WireAuth(type: "basic", basic: [AuthField(key: "username", value: user), AuthField(key: "password", value: password)])
        case .bearer(let token):
            return WireAuth(type: "bearer", bearer: [AuthField(key: "token", value: token)])
        }
    }

    private static func keyValue(_ row: Row) -> KeyValue {
        KeyValue(key: row.name, value: row.value, disabled: row.isEnabled ? nil : true)
    }

    // The wire shapes: Postman's keys, which a synthesized Encodable writes (nil is not written).

    private struct EnvFile: Encodable {
        var id: String
        var name: String
        var exportedAt: String
        var using: String
        var values: [EnvValue]

        enum CodingKeys: String, CodingKey {
            case id, name, values, color
            case scope = "_postman_variable_scope", exportedAt = "_postman_exported_at", using = "_postman_exported_using"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(values, forKey: .values)
            try container.encodeNil(forKey: .color)  // Postman writes the key; a synthesized Encodable would not
            try container.encode("environment", forKey: .scope)
            try container.encode(exportedAt, forKey: .exportedAt)
            try container.encode(using, forKey: .using)
        }
    }

    private struct EnvValue: Encodable {
        var key: String
        var value: String
        var type: String
        var enabled: Bool
    }

    private struct Root: Encodable {
        var info: Info
        var item: [Item]
    }

    private struct Info: Encodable {
        var name: String
        var id: String
        var schema: String
        enum CodingKeys: String, CodingKey { case name, id = "_postman_id", schema }
    }

    private struct Item: Encodable {
        var name: String
        var item: [Item]?
        var request: Req?
        var response: [String]?
        var protocolProfileBehavior: Behavior?
    }

    private struct Behavior: Encodable {
        var followRedirects: Bool
        var strictSSL: Bool?
        var disableBodyPruning: Bool?
    }

    private struct Req: Encodable {
        var method: String
        var url: WireURL
        var header: [KeyValue]
        var body: WireBody?
        var auth: WireAuth
    }

    private struct WireURL: Encodable {
        var raw: String
        var scheme: String?
        var host: [String]?
        var port: String?
        var path: [String]?
        var query: [KeyValue]?
        var variable: [KeyValue]?
        enum CodingKeys: String, CodingKey { case raw, scheme = "protocol", host, port, path, query, variable }
    }

    private struct KeyValue: Encodable {
        var key: String
        var value: String
        var disabled: Bool?
    }

    private struct WireBody: Encodable {
        var mode: String
        var raw: String?
        var options: RawOptions?
        var urlencoded: [KeyValue]?
        var formdata: [FormField]?
    }

    private struct RawOptions: Encodable { var raw: Language }
    private struct Language: Encodable { var language: String }

    private struct FormField: Encodable {
        var key: String
        var value: String?
        var type: String
        var src: String?
        var disabled: Bool?
    }

    private struct WireAuth: Encodable {
        var type: String
        var basic: [AuthField]?
        var bearer: [AuthField]?
    }

    private struct AuthField: Encodable {
        var key: String
        var value: String
        var type = "string"
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
