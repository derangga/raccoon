import Foundation

/// What the Body Type pop-up picks.
public enum BodyType: Equatable, Sendable {
    case none
    case raw(RawKind)
    case formURLEncoded
    case multipart
    case graphql
}

extension Body {
    public var type: BodyType {
        switch self {
        case .none: .none
        case .raw(let kind, _): .raw(kind)
        case .formURLEncoded: .formURLEncoded
        case .multipart: .multipart
        case .graphql: .graphql
        }
    }
}

public enum BodyConversion {
    /// raw → raw keeps the text, form ↔ multipart keeps the rows (text parts only), raw JSON ↔
    /// GraphQL lifts and rebuilds the JSON, anything → none keeps nothing, and every other pair
    /// starts empty.
    public static func convert(_ body: Body, to type: BodyType) -> Body {
        switch (body, type) {
        case (_, .none): .none
        case (.raw(_, let text), .raw(let kind)): .raw(kind, text)
        case (.graphql(let graphql), .raw(.json)): .raw(.json, GraphQLPayload.text(graphql))
        case (_, .raw(let kind)): .raw(kind, "")
        case (.formURLEncoded, .formURLEncoded), (.multipart, .multipart): body
        case (.multipart(let parts), .formURLEncoded):
            .formURLEncoded(parts.compactMap { part in
                guard case .text(let value) = part.content else { return nil }
                return Row(name: part.name, value: value, isEnabled: part.isEnabled)
            })
        case (_, .formURLEncoded): .formURLEncoded([])
        case (.formURLEncoded(let rows), .multipart):
            .multipart(rows.map { Part(name: $0.name, isEnabled: $0.isEnabled, content: .text($0.value)) })
        case (_, .multipart): .multipart([])
        case (.graphql, .graphql): body
        case (.raw(.json, let text), .graphql): .graphql(lift(text))
        case (_, .graphql): .graphql(GraphQLBody(query: "", variables: "", operationName: ""))
        }
    }

    /// The query, variables and operation name of a top-level JSON object; empty for anything else.
    /// Reads the text Format prints, so one member starts on a line with exactly two spaces and a
    /// quote or `{{`, a string never spans lines, and `{{name}}` is already accepted as a value. Variables
    /// keep their key order and number spelling.
    /// shortcut: a key written with escapes (`"qu\u0065ry"`) is not recognised, upgrade if one is ever seen.
    private static func lift(_ text: String) -> GraphQLBody {
        var body = GraphQLBody(query: "", variables: "", operationName: "")
        guard let formatted = try? BodyFormatter.format(text, kind: .json) else { return body }
        let lines = formatted.split(separator: "\n", omittingEmptySubsequences: false)
        // `{{name}}` as the whole document is one line too, so the opening line must be `{` alone.
        guard lines.first == "{" else { return body }
        var members: [String: [Substring]] = [:]
        var key: String?
        for line in lines.dropFirst().dropLast() {
            if line.hasPrefix("  \""), let split = line.firstRange(of: "\": ") {
                key = String(line[line.index(line.startIndex, offsetBy: 3)..<split.lowerBound])
                members[key!] = [line[split.upperBound...]]
            } else if line.hasPrefix("  {{") {
                key = nil  // a Variable as a key: a member of its own, never one of the three
            } else if let key {
                members[key]?.append(line)
            }
        }
        func value(_ key: String) -> String? {
            guard var text = members[key]?.joined(separator: "\n") else { return nil }
            if text.hasSuffix(",") { text.removeLast() }
            return text
        }
        func string(_ key: String) -> String {
            guard let text = value(key), text.hasPrefix("\"") else { return "" }
            return (try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)) as? String ?? ""
        }
        body.query = string("query")
        body.operationName = string("operationName")
        if let variables = value("variables"), variables != "null" {
            body.variables = (try? BodyFormatter.format(variables, kind: .json)) ?? ""
        }
        return body
    }
}

public enum Headers {
    /// Content-Type as a visible row. It is written only when the user has none, or when the row
    /// there is the one this rule wrote for the old Body Type: enabled, with that exact value.
    /// Multipart's row has no boundary; the transport appends it.
    public static func contentType(_ headers: [Row], from old: BodyType, to new: BodyType) -> [Row] {
        var headers = headers
        guard let index = headers.firstIndex(where: { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }) else {
            if let value = value(for: new) { headers.append(Row(name: "Content-Type", value: value)) }
            return headers
        }
        guard headers[index].isEnabled, headers[index].value == value(for: old) else { return headers }
        if let value = value(for: new) { headers[index].value = value } else { headers.remove(at: index) }
        return headers
    }

    private static func value(for type: BodyType) -> String? {
        switch type {
        case .none: nil
        case .raw(.json): "application/json"
        case .raw(.text): "text/plain"
        case .raw(.xml): "application/xml"
        case .formURLEncoded: "application/x-www-form-urlencoded"
        case .multipart: "multipart/form-data"
        case .graphql: "application/json"
        }
    }
}
