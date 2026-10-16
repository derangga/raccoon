import Foundation

/// The only way to a ResolvedRequest: Disabled Rows dropped, Auth turned into a header, and the
/// URL built once from the base and the percent-encoded params. Variable substitution comes
/// with the Variables feature.
public enum VariableResolver {
    public static func resolve(_ definition: RequestDefinition) throws(ResolveError) -> ResolvedRequest {
        var resolved = definition
        resolved.params = definition.params.filter(\.isEnabled)
        resolved.headers = definition.headers.filter(\.isEnabled) + authorization(definition.auth)
        resolved.cookies = definition.cookies.filter(\.isEnabled)
        resolved.body = switch definition.body {
        case .none, .raw: definition.body
        case .formURLEncoded(let rows): .formURLEncoded(rows.filter(\.isEnabled))
        case .multipart(let parts): .multipart(parts.filter(\.isEnabled))
        }
        resolved.auth = .none
        return ResolvedRequest(definition: resolved, url: try url(definition.url, params: resolved.params))
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
                URLQueryItem(name: encoded($0.name), value: encoded($0.value))
            }
        }
        guard let url = components.url else { throw .invalidURL(text) }
        return url
    }

    /// The query characters minus the ones that separate or alter a pair: `&`, `=`, `+`.
    private static let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))

    private static func encoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? text
    }
}
