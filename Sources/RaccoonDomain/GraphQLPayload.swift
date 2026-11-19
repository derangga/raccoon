import Foundation

/// The JSON a GraphQL body sends: `{"query", "variables", "operationName"}`, in that order, with
/// no added whitespace. The Variables object is embedded as typed (trimmed), never re-printed.
public enum GraphQLPayload {
    /// The inputs are already substituted. Empty Variables and an empty Operation Name are left
    /// out; Variables that are not a JSON object throw.
    public static func encode(query: String, variables: String, operationName: String) throws(ResolveError) -> String {
        let trimmed = variables.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            // Strict: a `{{name}}` that survived substitution is not JSON. The position is in the text as typed.
            do throws(FormatError) {
                _ = try BodyFormatter.format(variables, kind: .json, allowsVariables: false)
            } catch {
                switch error {
                case .notValid(let line, let column): throw .graphqlVariables(line: line, column: column)
                }
            }
            guard trimmed.hasPrefix("{") else {
                let (line, column) = position(ofFirstNonSpaceIn: variables)
                throw .graphqlVariables(line: line, column: column)
            }
        }
        return assemble(query: query, variables: trimmed, operationName: operationName)
    }

    /// What `encode` would build before resolution: the same shape, never throws and substitutes
    /// nothing. Variables that are not an object are kept as typed, so none of the text is lost.
    public static func text(_ body: GraphQLBody) -> String {
        assemble(query: body.query, variables: body.variables.trimmingCharacters(in: .whitespacesAndNewlines), operationName: body.operationName)
    }

    private static func assemble(query: String, variables: String, operationName: String) -> String {
        var members = ["\"query\":" + quoted(query)]
        if !variables.isEmpty { members.append("\"variables\":" + variables) }
        if !operationName.allSatisfy(\.isWhitespace) { members.append("\"operationName\":" + quoted(operationName)) }
        return "{" + members.joined(separator: ",") + "}"
    }

    /// A JSON string literal. Only what JSON requires is escaped, so a slash and non-ASCII text stay as typed.
    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{8}": out += "\\b"
            case "\u{c}": out += "\\f"
            case _ where scalar.value < 0x20: out += "\\u" + String(format: "%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// 1-based line and column of the first character that is not white space, counting Characters.
    private static func position(ofFirstNonSpaceIn text: String) -> (line: Int, column: Int) {
        var (line, column) = (1, 1)
        for char in text {
            if !char.isWhitespace { break }
            if char.isNewline { (line, column) = (line + 1, 1) } else { column += 1 }
        }
        return (line, column)
    }
}
