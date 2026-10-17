import Foundation

/// Curl Import: pasted text to the parts of a request definition. Pure; reading `@path`s is
/// left to the caller (fileReferences).
public enum CurlImporter {
    public static func `import`(_ text: String) throws(CurlImportError) -> CurlImport {
        let (words, skipped) = try CurlLexer.commands(text)
        var curlImport = try CurlMapping.definition(CurlFlags.collect(CurlLexer.expandShortFlags(words)))
        curlImport.skippedCommands = skipped
        return curlImport
    }
}

public enum CurlMapping {
    public static func definition(_ flags: CurlFlags) throws(CurlImportError) -> CurlImport {
        guard let urlText = flags.values("url").first ?? flags.positionals.first, !urlText.isEmpty else { throw .noURL }
        let (url, query) = URLText.split(urlText)
        var ignoredFlags = flags.ignoredFlags
        var headers = flags.values("header").map(header)

        // curl reads cookies from a file when the value has no `=`; Raccoon does not.
        let cookieValues = flags.values("cookie")
        if cookieValues.contains(where: { !$0.contains("=") }) { ignoredFlags.append("--cookie") }
        let isCookie = { (row: Row) in row.name.caseInsensitiveCompare("Cookie") == .orderedSame }
        let cookies = (cookieValues.filter { $0.contains("=") } + headers.filter(isCookie).map(\.value)).flatMap(cookieRows)
        headers.removeAll(where: isCookie)

        let auth: Auth
        if let index = headers.firstIndex(where: { $0.name.caseInsensitiveCompare("Authorization") == .orderedSame }) {
            auth = authorization(headers[index].value)
            if auth != .none { headers.remove(at: index) }
        } else if let user = flags.values("user").first {
            let (name, password) = splitOnce(user, ":")
            auth = .basic(user: name, password: password ?? "")
        } else {
            auth = .none
        }

        let body = Body.none
        return CurlImport(
            definition: RequestDefinition(
                method: flags.values("request").last?.uppercased() ?? (body == .none ? "GET" : "POST"),
                url: url,
                params: query + flags.values("url-query").map { pair in
                    let (name, value) = splitOnce(pair, "=")
                    return Row(name: name, value: value ?? "")
                },
                headers: headers,
                cookies: cookies,
                body: body,
                auth: auth,
                settings: RequestSettings(allowsInsecureTLS: flags.has("insecure"), followsRedirects: flags.has("location"))
            ),
            ignoredFlags: ignoredFlags,
            fileReferences: [],
            skippedCommands: 0
        )
    }

    /// `Name: value`, trimmed; `Name;` is the empty header.
    private static func header(_ text: String) -> Row {
        let (name, value) = splitOnce(text, ":")
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let value else { return Row(name: trimmed.hasSuffix(";") ? String(trimmed.dropLast()) : trimmed, value: "") }
        return Row(name: trimmed, value: value.trimmingCharacters(in: .whitespaces))
    }

    /// `a=1; b=2` → two rows.
    private static func cookieRows(_ text: String) -> [Row] {
        text.split(separator: ";").compactMap { pair in
            let pair = pair.trimmingCharacters(in: .whitespaces)
            guard !pair.isEmpty else { return nil }
            let (name, value) = splitOnce(pair, "=")
            return Row(name: name, value: value ?? "")
        }
    }

    /// `Bearer x`, or `Basic` whose base64 decodes to `user:pass`; anything else stays a header.
    private static func authorization(_ value: String) -> Auth {
        let (scheme, credentials) = splitOnce(value.trimmingCharacters(in: .whitespaces), " ")
        guard let credentials = credentials?.trimmingCharacters(in: .whitespaces), !credentials.isEmpty else { return .none }
        switch scheme.lowercased() {
        case "bearer":
            return .bearer(token: credentials)
        case "basic":
            guard let data = Data(base64Encoded: credentials), let decoded = String(data: data, encoding: .utf8) else { return .none }
            let (user, password) = splitOnce(decoded, ":")
            guard let password, !user.isEmpty else { return .none }
            return .basic(user: user, password: password)
        default:
            return .none
        }
    }

    /// Only the first separator splits: `token=abc==` keeps its padding.
    private static func splitOnce(_ text: String, _ separator: Character) -> (String, String?) {
        guard let index = text.firstIndex(of: separator) else { return (text, nil) }
        return (String(text[..<index]), String(text[text.index(after: index)...]))
    }
}
