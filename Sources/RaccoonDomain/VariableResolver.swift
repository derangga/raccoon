import Foundation

/// The only way to a ResolvedRequest: Disabled Rows dropped, every `{{name}}` substituted from
/// the scope, Auth turned into a header, and the URL built once from the base and the
/// percent-encoded params.
public enum VariableResolver {
    /// One pass, not recursive: a value of `{{other}}` is sent as that text. Every Undefined
    /// Variable is collected and thrown together, in the order they appear.
    public static func resolve(
        _ definition: RequestDefinition, scope: VariableScope = VariableScope(values: [:])
    ) throws(ResolveError) -> ResolvedRequest {
        var undefined: [VariableName] = []
        func text(_ text: String) -> String { substitute(text, scope, &undefined) }
        func rows(_ rows: [Row]) -> [Row] {
            rows.filter(\.isEnabled).map { Row(name: text($0.name), value: text($0.value)) }
        }

        var resolved = definition
        resolved.url = urlText(definition, scope, &undefined)
        resolved.params = rows(definition.params)
        resolved.headers = rows(definition.headers)
        resolved.cookies = rows(definition.cookies)
        resolved.pathVariables = [:]
        resolved.body = switch definition.body {
        case .none: .none
        case .raw(let kind, let body): .raw(kind, text(body))
        case .formURLEncoded(let form): .formURLEncoded(rows(form))
        case .multipart(let parts): .multipart(parts.filter(\.isEnabled).map { part in
            switch part.content {
            case .text(let value): Part(name: text(part.name), content: .text(text(value)))
            case .file(let path): Part(name: text(part.name), content: .file(path: text(path)))
            }
        })
        }
        let auth: Auth = switch definition.auth {
        case .none: .none
        case .basic(let user, let password): .basic(user: text(user), password: text(password))
        case .bearer(let token): .bearer(token: text(token))
        }
        guard undefined.isEmpty else { throw .undefined(undefined) }
        // Rows are enabled only by now; a repeated name would be joined into one header at send.
        if !resolved.headers.contains(where: \.winsOverAuth) { resolved.headers += authorization(auth) }
        resolved.auth = .none
        return ResolvedRequest(definition: resolved, url: try url(resolved.url, params: resolved.params))
    }

    /// The typed URL in one left-to-right pass: each `{{name}}` is its value and each `:name` the
    /// Path Variable's value, substituted and then encoded as a path segment. A value's own text is
    /// never read again, so a Variable cannot create a Path Variable. A name with no value, or a
    /// value that resolves to "", stays `:name` as typed.
    private static func urlText(_ definition: RequestDefinition, _ scope: VariableScope, _ undefined: inout [VariableName]) -> String {
        let source = definition.url as NSString
        // A Variable's range and a Path Variable's never overlap: `{` is not a name character.
        let pieces: [(range: NSRange, pathName: String?)] = (VariableTokens.ranges(definition.url).map { ($0.range, nil) }
            + PathVariables.tokens(in: definition.url).map { ($0.range, $0.name) })
            .sorted { $0.range.location < $1.range.location }
        var result = ""
        var last = 0
        for (range, pathName) in pieces {
            result += source.substring(with: NSRange(location: last, length: range.location - last))
            let typed = source.substring(with: range)
            if let pathName {
                let value = definition.pathVariables[pathName].map { substitute($0, scope, &undefined) } ?? ""
                result += value.isEmpty ? typed : PathEncoding.segment(value)
            } else {
                result += substitute(typed, scope, &undefined)
            }
            last = NSMaxRange(range)
        }
        return result + source.substring(from: last)
    }

    /// Token ranges start at `{` and end at `}`, so cutting at them never splits a character.
    private static func substitute(_ text: String, _ scope: VariableScope, _ undefined: inout [VariableName]) -> String {
        let tokens = VariableTokens.ranges(text)
        guard !tokens.isEmpty else { return text }
        let source = text as NSString
        var result = ""
        var last = 0
        for token in tokens {
            result += source.substring(with: NSRange(location: last, length: token.range.location - last))
            if let value = scope.values[token.name] {
                result += value
            } else {
                if !undefined.contains(token.name) { undefined.append(token.name) }
                result += source.substring(with: token.range)
            }
            last = NSMaxRange(token.range)
        }
        return result + source.substring(from: last)
    }

    private static func authorization(_ auth: Auth) -> [Row] {
        switch auth {
        case .none: []
        case .basic(let user, let password): [Row(name: "Authorization", value: "Basic \(Data("\(user):\(password)".utf8).base64EncodedString())")]
        case .bearer(let token): [Row(name: "Authorization", value: "Bearer \(token)")]
        }
    }

    /// Values are stored decoded and encoded here, once, so a value holding `&` stays one param.
    private static func url(_ text: String, params: [Row]) throws(ResolveError) -> URL {
        guard var components = URLComponents(string: text), components.scheme != nil, components.host?.isEmpty == false else {
            throw .invalidURL(text)
        }
        if !params.isEmpty {
            components.percentEncodedQueryItems = params.map {
                URLQueryItem(name: QueryEncoding.name($0.name), value: QueryEncoding.value($0.value))
            }
        }
        guard let url = components.url else { throw .invalidURL(text) }
        return url
    }
}
