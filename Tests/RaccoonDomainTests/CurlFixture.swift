import RaccoonDomain
import Testing

/// One pasted command and what Curl Import must make of it.
struct CurlFixture: Sendable, CustomTestStringConvertible {
    let name: String
    let input: String
    let expected: Result<CurlImport, CurlImportError>

    var testDescription: String { name }

    init(_ name: String, _ input: String, _ expected: CurlImport) {
        self.name = name
        self.input = input
        self.expected = .success(expected)
    }

    init(_ name: String, _ input: String, throws error: CurlImportError) {
        self.name = name
        self.input = input
        self.expected = .failure(error)
    }
}

func request(
    _ url: String, method: String = "GET", params: [Row] = [], headers: [Row] = [], cookies: [Row] = [],
    body: Body = .none, auth: Auth = .none, insecure: Bool = false, redirects: Bool = false,
    ignored: [String] = [], files: [String] = [], skipped: Int = 0
) -> CurlImport {
    CurlImport(
        definition: RequestDefinition(
            method: method, url: url, params: params, headers: headers, cookies: cookies, body: body, auth: auth,
            settings: RequestSettings(allowsInsecureTLS: insecure, followsRedirects: redirects)
        ),
        ignoredFlags: ignored, fileReferences: files, skippedCommands: skipped
    )
}

func rows(_ pairs: (String, String)...) -> [Row] {
    pairs.map { Row(name: $0.0, value: $0.1) }
}

func parts(_ parts: (String, Part.Content)...) -> Body {
    .multipart(parts.map { Part(name: $0.0, content: $0.1) })
}
