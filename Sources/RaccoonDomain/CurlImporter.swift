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
        let (url, query) = URLText.split(urlText.contains("://") ? urlText : "http://" + urlText)
        var ignoredFlags = flags.ignoredFlags
        var headers = flags.options.compactMap { option in
            switch (option.name, option.value) {
            case ("header", let value?): header(value)
            case ("user-agent", let value?): Row(name: "User-Agent", value: value)
            default: nil
            }
        }
        if flags.has("json") {
            for name in ["Content-Type", "Accept"] where !headers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                headers.append(Row(name: name, value: "application/json"))
            }
        }

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

        let contentType = headers.first { $0.name.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value
        let (body, dataParams, fileReferences) = body(flags, contentType: contentType)
        return CurlImport(
            definition: RequestDefinition(
                method: flags.values("request").last?.uppercased() ?? (flags.has("head") ? "HEAD" : body == .none ? "GET" : "POST"),
                url: url,
                params: query + flags.values("url-query").map { pair in
                    let (name, value) = splitOnce(pair, "=")
                    return Row(name: name, value: value ?? "")
                } + dataParams,
                headers: headers,
                cookies: cookies,
                body: body,
                auth: auth,
                settings: RequestSettings(allowsInsecureTLS: flags.has("insecure"), followsRedirects: flags.has("location"))
            ),
            ignoredFlags: ignoredFlags,
            fileReferences: fileReferences,
            skippedCommands: 0
        )
    }

    /// The body table in curl.md: the first matching row wins. `-G` turns the data into params
    /// instead, and an `@path` leaves the text to be read.
    private static func body(_ flags: CurlFlags, contentType: String?) -> (Body, params: [Row], fileReferences: [String]) {
        let forms = flags.values("form")
        if !forms.isEmpty { return (.multipart(forms.map(part)), [], []) }
        let data = flags.options.compactMap { option in
            dataFlags.contains(option.name) ? option.value.map { (flag: option.name, value: $0) } : nil
        }
        guard !data.isEmpty else { return (.none, [], []) }
        if flags.has("get") { return (.none, data.flatMap(formRows), []) }

        let mediaType = contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
        let text = data.map(\.value).joined(separator: "&")
        if mediaType == "multipart/form-data",
           let boundary = contentType?.firstMatch(of: /(?i)boundary=([^\s;]+)/)?.output.1,
           let parts = multipart(text, boundary: boundary.trimmingCharacters(in: CharacterSet(charactersIn: "\""))) {
            return (.multipart(parts), [], [])
        }
        // curl reads the file for every data flag but --data-raw; --data-urlencode's @ is not a body.
        let files = data.filter { !["data-raw", "data-urlencode"].contains($0.flag) && $0.value.hasPrefix("@") }
        if !files.isEmpty { return (.raw(rawKind(mediaType), ""), [], files.map { String($0.value.dropFirst()) }) }
        if data.allSatisfy({ ["data", "data-ascii", "data-urlencode"].contains($0.flag) }),
           mediaType == nil || mediaType == "application/x-www-form-urlencoded" {
            return (.formURLEncoded(data.flatMap(formRows)), [], [])
        }
        return (.raw(rawKind(mediaType), text), [], [])
    }

    private static let dataFlags: Set<String> = ["data", "data-ascii", "data-binary", "data-raw", "data-urlencode", "json"]

    /// json and xml by name, so `application/vnd.api+json` and `text/xml` count; anything else is text.
    private static func rawKind(_ mediaType: String?) -> RawKind {
        guard let mediaType else { return .text }
        if mediaType.contains("json") { return .json }
        if mediaType.contains("xml") { return .xml }
        return .text
    }

    /// `-d` splits at `&` then the first `=`, decoded. `--data-urlencode` is one value curl encodes
    /// itself, so it is neither split nor decoded.
    private static func formRows(_ data: (flag: String, value: String)) -> [Row] {
        if data.flag == "data-urlencode" {
            let (name, value) = splitOnce(data.value, "=")
            return [Row(name: name, value: value ?? "")]
        }
        return data.value.split(separator: "&").map { pair in
            let (name, value) = splitOnce(String(pair), "=")
            return Row(name: percentDecoded(name), value: percentDecoded(value ?? ""))
        }
    }

    /// Each valid `%XX` run decoded and the rest kept, so `100%` is not an error.
    private static func percentDecoded(_ text: String) -> String {
        text.removingPercentEncoding ?? text.replacing(/(?:%[0-9A-Fa-f]{2})+/) { run in
            run.output.removingPercentEncoding ?? String(run.output)
        }
    }

    /// `name=value` or `name=@path`; a `;type=…` after the path is dropped.
    private static func part(_ text: String) -> Part {
        let (name, value) = splitOnce(text, "=")
        let content = value ?? ""
        guard content.hasPrefix("@") else { return Part(name: name, content: .text(content)) }
        return Part(name: name, content: .file(path: String(content.dropFirst().prefix { $0 != ";" })))
    }

    /// What Chrome's Copy as cURL writes for a multipart body: a file part names its file but not
    /// its bytes, so it imports as that file name. nil when no part parses.
    private static func multipart(_ raw: String, boundary: String) -> [Part]? {
        let parts = raw.components(separatedBy: "--" + boundary).compactMap { chunk -> Part? in
            guard let split = chunk.range(of: "\r\n\r\n"),
                  let disposition = chunk[..<split.lowerBound].firstMatch(of: /(?i)content-disposition:\s*form-data;\s*name="([^"]*)"(?:;\s*filename="([^"]*)")?/)
            else { return nil }
            if let filename = disposition.output.2 { return Part(name: String(disposition.output.1), content: .file(path: String(filename))) }
            var content = chunk[split.upperBound...]
            if content.hasSuffix("\r\n") { content = content.dropLast() }
            return Part(name: String(disposition.output.1), content: .text(String(content)))
        }
        return parts.isEmpty ? nil : parts
    }

    /// `Name: value`, trimmed; `Name;` is the empty header.
    private static func header(_ text: String) -> Row {
        let (name, value) = splitOnce(text, ":")
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let value else { return Row(name: trimmed.hasSuffix(";") ? String(trimmed.dropLast()) : trimmed, value: "") }
        return Row(name: trimmed, value: value.trimmingCharacters(in: .whitespaces))
    }

    /// `a=1; b=2` → two rows; `secure` is an attribute, not a cookie. Postman Import splits its
    /// Cookie headers the same way.
    static func cookieRows(_ text: String) -> [Row] {
        text.split(separator: ";").compactMap { pair in
            let pair = pair.trimmingCharacters(in: .whitespaces)
            guard pair.contains("=") else { return nil }
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
