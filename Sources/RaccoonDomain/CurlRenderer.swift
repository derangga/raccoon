/// Copy as Curl and the Curl pane: a ResolvedRequest as the command board 11 shows. What
/// CurlImporter reads back is the same request (curl.md, the round trip).
public enum CurlRenderer {
    public static func render(_ request: ResolvedRequest) -> String {
        let definition = request.definition
        var first = ["curl"]
        if definition.method != "GET" || definition.body != .none {
            first += ["-X", definition.method.allSatisfy { $0.isASCII && $0.isLetter } ? definition.method : quoted(definition.method)]
        }
        first.append(quoted(request.url.absoluteString))

        var flags = definition.headers.map { "-H " + quoted($0.value.isEmpty ? "\($0.name);" : "\($0.name): \($0.value)") }
        if !definition.cookies.isEmpty {
            flags.append("-b " + quoted(definition.cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")))
        }
        switch definition.body {
        case .none:
            break
        case .raw(_, let text):
            flags.append("--data-raw " + quoted(text))
        case .formURLEncoded(let rows):
            flags += rows.map { "--data-urlencode " + quoted("\($0.name)=\($0.value)") }
        case .multipart(let parts):
            flags += parts.map { part in
                switch part.content {
                case .text(let value): "-F " + quoted("\(part.name)=\(value)")
                case .file(let path): "-F " + quoted("\(part.name)=@\(path)")
                }
            }
        }
        if definition.settings.allowsInsecureTLS { flags.append("-k") }
        if definition.settings.followsRedirects { flags.append("-L") }
        return ([first.joined(separator: " ")] + flags).joined(separator: " \\\n  ")
    }

    private static func quoted(_ text: String) -> String {
        "'" + text.replacing("'", with: #"'\''"#) + "'"
    }
}
