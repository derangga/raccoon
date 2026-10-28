/// Copy as Curl and the Curl pane: a ResolvedRequest as the command board 11 shows. What
/// CurlImporter reads back is the same request (curl.md, the round trip).
public enum CurlRenderer {
    public static func render(_ request: ResolvedRequest) -> String {
        let definition = request.definition
        var first = ["curl"]
        if definition.method != "GET" || definition.body != .none {
            first += ["-X", definition.method.allSatisfy { $0.isASCII && $0.isLetter } ? definition.method : quoted(definition.method)]
        }
        first.append(quoted(keepingVariables(request.url.absoluteString)))

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

    /// A Secret Variable left as `{{name}}` (secrets off) went through the URL's percent-encoding as
    /// `%7B%7Bname%7D%7D`: show it as written. A name has no character that encoding touches.
    private static func keepingVariables(_ url: String) -> String {
        url.replacing(/%7B%7B([A-Za-z0-9_.\-]+)%7D%7D/) { "{{\($0.output.1)}}" }
    }

    private static func quoted(_ text: String) -> String {
        "'" + text.replacing("'", with: #"'\''"#) + "'"
    }
}

/// The Curl pane (curl.md §The Curl pane): the command Copy as Curl would render, or why there
/// is none. The caller's scope decides what a secret shows; the pane passes one that keeps it
/// as `{{name}}`.
public enum CurlPreview: Equatable, Sendable {
    case command(String)
    case undefined([VariableName])
    /// A blank URL: nothing to render yet, whatever else is missing.
    case noURL
    /// The URL after substitution.
    case invalidURL(String)

    public init(_ definition: RequestDefinition, scope: VariableScope) {
        guard !definition.url.allSatisfy(\.isWhitespace) else {
            self = .noURL
            return
        }
        do throws(ResolveError) {
            self = .command(CurlRenderer.render(try VariableResolver.resolve(definition, scope: scope)))
        } catch {
            switch error {
            case .undefined(let names): self = .undefined(names)
            case .invalidURL(let text): self = .invalidURL(text)
            }
        }
    }
}
