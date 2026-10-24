import Foundation

/// Postman Import's reading half: export bytes to a PostmanFile, in Postman's own terms. Pure,
/// and never throws: anything it does not recognise is .notPostman. Postman's files vary in type
/// from key to key (a url string or object, a number where a string was expected, `null`), so
/// they are read as JSON objects and settled here, never by a synthesised Decodable.
public enum PostmanImporter {
    private typealias Object = [String: Any]

    private static let schemas: Set = [
        "https://schema.getpostman.com/json/collection/v2.0.0/collection.json",
        "https://schema.getpostman.com/json/collection/v2.1.0/collection.json",
    ]

    public static func read(_ data: Data) -> PostmanFile {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? Object else { return .notPostman }
        let info = root["info"] as? Object ?? [:]
        if let schema = info["schema"] as? String, schemas.contains(schema), let items = root["item"] as? [Any] {
            return .collection(PostmanCollection(
                name: text(info["name"]) ?? "", description: description(info["description"]), items: objects(items).map(item),
                auth: auth(root["auth"]), events: events(root["event"]), variables: variables(root["variable"])
            ))
        }
        let values = root["values"] as? [Any]
        switch root["_postman_variable_scope"] as? String {
        case "globals": return .globals(variables(values))
        case "environment", nil:
            guard let values, let name = text(root["name"]) else { return .notPostman }
            return .environment(PostmanEnvironment(name: name, values: variables(values)))
        default: return .notPostman
        }
    }

    /// Environment and Globals `values` say `enabled`; a collection's `variable` says `disabled`.
    private static func variables(_ json: Any?) -> [PostmanVariable] {
        objects(json).map { variable in
            PostmanVariable(
                key: text(variable["key"]) ?? "", value: text(variable["value"]) ?? "",
                enabled: variable["enabled"] as? Bool ?? !(variable["disabled"] as? Bool ?? false), type: text(variable["type"])
            )
        }
    }

    private static func item(_ json: Object) -> PostmanItem {
        let name = text(json["name"]) ?? ""
        if let items = json["item"] as? [Any] {
            return .folder(PostmanFolder(
                name: name, description: description(json["description"]), items: objects(items).map(item),
                auth: auth(json["auth"]), events: events(json["event"])
            ))
        }
        // `request` may be a bare URL string.
        let request: Object
        switch json["request"] {
        case let object as Object: request = object
        case let url as String: request = ["url": url]
        default: return .other(name: name)
        }
        let behavior = json["protocolProfileBehavior"] as? Object ?? [:]
        return .request(PostmanRequest(
            name: name, description: description(request["description"]) ?? description(json["description"]),
            method: text(request["method"]) ?? "GET", url: url(request["url"]), headers: keyValues(request["header"]),
            body: body(request["body"]), auth: auth(request["auth"]),
            followRedirects: behavior["followRedirects"] as? Bool, strictSSL: behavior["strictSSL"] as? Bool,
            events: events(json["event"]), responseCount: (json["response"] as? [Any])?.count ?? 0
        ))
    }

    private static func url(_ json: Any?) -> PostmanURL {
        if let raw = json as? String { return PostmanURL(raw: raw) }
        guard let url = json as? Object else { return PostmanURL() }
        return PostmanURL(
            raw: text(url["raw"]), protocol: text(url["protocol"]), host: segments(url["host"], separator: "."),
            port: text(url["port"]), path: segments(url["path"], separator: "/"),
            query: keyValues(url["query"]), variable: keyValues(url["variable"]), hash: text(url["hash"])
        )
    }

    private static func body(_ json: Any?) -> PostmanBody? {
        guard let body = json as? Object else { return nil }
        switch text(body["mode"]) {
        case "raw":
            let language = ((body["options"] as? Object)?["raw"] as? Object)?["language"]
            return .raw(text(body["raw"]) ?? "", language: text(language))
        case "urlencoded":
            return .urlencoded(keyValues(body["urlencoded"]))
        case "formdata":
            return .formdata(objects(body["formdata"]).map { parameter in
                let src = parameter["src"]
                let content: PostmanFormParameter.Content = text(parameter["type"]) == "file" || text(src) != nil
                    ? .file(src: (src as? [Any])?.compactMap(text) ?? text(src).map { [$0] } ?? [])
                    : .text(text(parameter["value"]) ?? "")
                return PostmanFormParameter(key: text(parameter["key"]) ?? "", content: content, disabled: parameter["disabled"] as? Bool ?? false)
            })
        case "graphql":
            let graphql = body["graphql"] as? Object ?? [:]
            return .graphql(query: text(graphql["query"]) ?? "", variables: text(graphql["variables"]) ?? "")
        case "file":
            return .file(src: text((body["file"] as? Object)?["src"]))
        default:
            return nil
        }
    }

    /// Parameters are `[{key, value}]`, or in v2.0 an object. Absent means inherit.
    private static func auth(_ json: Any?) -> PostmanAuth? {
        guard let auth = json as? Object, let type = text(auth["type"]) else { return nil }
        let parameters: [(String, String)] = if let object = auth[type] as? Object {
            object.map { ($0.key, text($0.value) ?? "") }
        } else {
            objects(auth[type]).compactMap { parameter in text(parameter["key"]).map { ($0, text(parameter["value"]) ?? "") } }
        }
        return PostmanAuth(type: type, parameters: Dictionary(parameters) { _, last in last })
    }

    /// `exec` is an array of lines, or one string.
    private static func events(_ json: Any?) -> [PostmanEvent] {
        objects(json).map { event in
            let script = event["script"] as? Object ?? [:]
            let exec = (script["exec"] as? [Any])?.compactMap(text).joined(separator: "\n") ?? text(script["exec"]) ?? ""
            return PostmanEvent(listen: text(event["listen"]) ?? "", exec: exec)
        }
    }

    /// A string, or `{content, type}`.
    private static func description(_ json: Any?) -> String? {
        (json as? Object).map { text($0["content"]) } ?? text(json)
    }

    /// An array as it is, or a string split on `separator`, without a leading one.
    private static func segments(_ json: Any?, separator: Character) -> [String]? {
        if let array = json as? [Any] { return array.compactMap(text) }
        guard let string = text(json) else { return nil }
        let trimmed = string.drop { $0 == separator }
        return trimmed.isEmpty ? [] : trimmed.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
    }

    private static func keyValues(_ json: Any?) -> [PostmanKeyValue] {
        objects(json).map { PostmanKeyValue(key: text($0["key"]) ?? "", value: text($0["value"]) ?? "", disabled: $0["disabled"] as? Bool ?? false) }
    }

    /// The objects of an array; anything else in it, or a non-array, is skipped.
    private static func objects(_ json: Any?) -> [Object] {
        (json as? [Any])?.compactMap { $0 as? Object } ?? []
    }

    /// Any JSON value as text: a number or bool as written, an object or array as JSON. `null` is nil.
    private static func text(_ json: Any?) -> String? {
        switch json {
        case let string as String: string
        case let number as NSNumber:
            CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        case let other? where JSONSerialization.isValidJSONObject(other):
            (try? JSONSerialization.data(withJSONObject: other, options: [.sortedKeys, .withoutEscapingSlashes]))
                .map { String(decoding: $0, as: UTF8.self) }
        default: nil
        }
    }
}
